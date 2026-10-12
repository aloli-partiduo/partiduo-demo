# SPDX-License-Identifier: AGPL-3.0-or-later

require "yaml"
require "csv"
require "big"

module PartiduoDemo
  module Validation
    # Taux de TVA du socle (régime fr), en pourcentage, par code.
    STANDARD_RATES = {
      "NOR" => "20", "INT" => "10", "TR55" => "5.5", "TP021" => "2.1", "DNOR" => "8.5", "DR" => "2.1", "DPRS" => "1.05",
      "DOM1" => "1.75", "COR13" => "13", "COR09" => "0.9", "EXP" => "0", "INTL" => "0", "AUTOL" => "0", "INTS" => "20",
      "FRANC" => "0",
    }

    # Dossier lu dans son répertoire : fichiers YAML bruts, contrôlés contre
    # le schéma, puis références, équilibres, relevés, secrets et cohérence
    # des résultats attendus.
    class DossierCheck
      FILES = {
        "dossier.yml"     => "dossier",
        "referentiel.yml" => "referentiel",
        "parametres.yml"  => "parametres",
        "operations.yml"  => "operations",
        "attendus.yml"    => "attendus",
      }

      getter directory : String
      getter errors = [] of String
      getter notes = [] of String
      getter dates : Dates
      getter files = {} of String => YAML::Any
      # Mouvements des relevés importés, recalculés par `Statements`.
      getter statement_postings = [] of Posting

      def initialize(@directory : String, today : Time)
        @dates = Dates.new(today)
      end

      def code : String
        File.basename(directory)
      end

      def run : Nil
        FILES.each do |name, structure|
          node = parse(name) || next
          checker = Checker.new(@errors)
          checker.check(node, structure, "#{relative(name)}")
          @files[name] = node
          format = node["format"]?.try(&.raw)
          error(relative(name), "format #{format} inconnu (attendu : 1)") unless format == 1
        end
        return unless @files.size == FILES.size
        if identity["code"]?.try(&.as_s?) != code
          error(relative("dossier.yml"), "code différent du répertoire « #{code} »")
        end
        References.new(self).run
        Statements.new(self).run
        Secrets.new(self).run
        Expectations.new(self).run
      end

      def parse(name : String) : YAML::Any?
        path = File.join(directory, name)
        unless File.exists?(path)
          error(relative(name), "fichier absent")
          return
        end
        YAML.parse(File.read(path))
      rescue ex : YAML::ParseException
        error(relative(name), "YAML illisible : #{ex.message}")
        nil
      end

      def relative(name : String) : String
        "#{code}/#{name}"
      end

      def error(where : String, message : String) : Nil
        @errors << "#{where} : #{message}"
      end

      def note(message : String) : Nil
        @notes << message
      end

      def identity : YAML::Any
        files["dossier.yml"]
      end

      def reference : YAML::Any
        files["referentiel.yml"]
      end

      def parameters : YAML::Any
        files["parametres.yml"]
      end

      def expected : YAML::Any
        files["attendus.yml"]
      end

      # Opérations de chaque section, avec leur emplacement.
      def operations : Array({String, YAML::Any})
        list = [] of {String, YAML::Any}
        %w[operations recentes fin].each do |section|
          (files["operations.yml"][section]?.try(&.as_a?) || [] of YAML::Any).each_with_index do |operation, index|
            list << {"operations.yml : #{section}[#{index}] (#{operation["type"]?.try(&.as_s?)})", operation}
          end
        end
        list
      end

      # Opérations datées (sections `operations` et `recentes`) jouées pour
      # le jour de chargement : date résolue, condition `si` remplie, date
      # au plus tard ce jour-là.
      def dated_operations : Array({Time, YAML::Any})
        list = [] of {Time, YAML::Any}
        %w[operations recentes].each do |section|
          (files["operations.yml"][section]?.try(&.as_a?) || [] of YAML::Any).each do |operation|
            text = operation["date"]?.try(&.as_s?) || next
            next unless Dates.date?(text)
            day = dates.date(text)
            next unless applies?(operation["si"]?, day) && day <= dates.today
            list << {day, operation}
          end
        end
        list
      end

      def applies?(condition : YAML::Any?, day : Time) : Bool
        return true unless condition
        if text = condition["depuis"]?.try(&.as_s?)
          return false if Dates.date?(text) && day < dates.date(text)
        end
        if text = condition["avant"]?.try(&.as_s?)
          return false if Dates.date?(text) && !(day < dates.date(text))
        end
        true
      end

      def list(node : YAML::Any?, key : String) : Array(YAML::Any)
        node.try(&.[key]?).try(&.as_a?) || [] of YAML::Any
      end

      def text(node : YAML::Any?, key : String) : String?
        node.try(&.[key]?).try(&.as_s?)
      end

      def amount(text : String?) : BigDecimal
        BigDecimal.new(text || "0")
      rescue InvalidBigDecimalException
        BigDecimal.new(0)
      end

      def quantity(node : YAML::Any?) : BigDecimal
        raw = node.try(&.raw)
        case raw
        when Int64  then BigDecimal.new(raw)
        when String then amount(raw)
        else             BigDecimal.new(0)
        end
      end

      # Articles du référentiel, par code.
      def items : Hash(String, YAML::Any)
        @items ||= list(reference, "articles").each_with_object({} of String => YAML::Any) do |item, hash|
          text(item, "code").try { |key| hash[key] = item }
        end
      end

      @items : Hash(String, YAML::Any)? = nil

      # Taux de TVA connus (socle et référentiel), en pourcentage.
      def rates : Hash(String, BigDecimal)
        rates = STANDARD_RATES.transform_values { |value| BigDecimal.new(value) }
        list(reference, "taux_tva").each do |rate|
          code = text(rate, "code") || next
          rates[code] = amount(text(rate, "taux"))
        end
        rates
      end
    end
  end
end
