# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDemo
  module Validation
    # Mouvement comptable recalculé : date, compte, montant signé (débit
    # positif).
    record Posting, day : Time, account : String, amount : BigDecimal

    # Relevés importés (`import_releve`) : lus avec leur format CSV, chaque
    # ligne doit trouver une règle de catégorisation ; soldes de début et
    # de fin cohérents avec les lignes, et d'un relevé au suivant.
    class Statements
      def initialize(@dossier : DossierCheck)
      end

      def run : Nil
        formats = @dossier.list(@dossier.parameters["bankimport"]?, "formats")
        rules = @dossier.list(@dossier.parameters["bankimport"]?, "regles")
        previous = {} of String => BigDecimal
        imports = @dossier.operations.select { |(_, operation)| @dossier.text(operation, "type") == "import_releve" }
        imports.each do |(where, operation)|
          file = @dossier.text(operation, "fichier") || next
          path = File.join(@dossier.directory, file)
          next if file.includes?("..") || !File.exists?(path)
          name = @dossier.text(operation, "format")
          format = formats.find { |item| @dossier.text(item, "nom") == name } || formats.first? || next
          lines = read(where, file, File.read(path), format) || next
          bank = @dossier.text(format, "compte") || ""
          total = BigDecimal.new(0)
          lines.each do |(day, label, amount)|
            total += amount
            account = categorize(label, amount, rules)
            unless account
              @dossier.error(@dossier.relative(file), "« #{label} » : aucune règle de catégorisation ne s'applique")
              next
            end
            @dossier.statement_postings << Posting.new(day, bank, amount)
            @dossier.statement_postings << Posting.new(day, account, -amount)
          end
          statement = operation["pointage"]?
          start = @dossier.text(statement, "solde_debut")
          finish = @dossier.text(statement, "solde_fin")
          if start && finish
            if @dossier.amount(start) + total != @dossier.amount(finish)
              @dossier.error(@dossier.relative(file), "solde de début #{start} + mouvements #{total} ≠ solde de fin #{finish}")
            end
            last = previous[bank]?
            if last && last != @dossier.amount(start)
              @dossier.error(@dossier.relative(file), "solde de début #{start} ≠ solde de fin du relevé précédent #{last}")
            end
            previous[bank] = @dossier.amount(finish)
          end
        end
      end

      # Lignes du relevé : date, libellé, montant signé (crédit positif).
      private def read(where : String, file : String, content : String, format : YAML::Any) : Array({Time, String, BigDecimal})?
        separator = {"comma" => ',', "semicolon" => ';', "tab" => '\t', "pipe" => '|'}[@dossier.text(format, "separateur") || "semicolon"]
        decimal = @dossier.text(format, "separateur_decimal") == "dot" ? '.' : ','
        skip = format["lignes_entete"]?.try(&.as_i?) || 1
        columns = format["colonnes"]?
        column = ->(key : String) { columns.try(&.[key]?).try(&.as_i?) }
        rows = CSV.parse(@dossier.dates.expand_years(content), separator: separator)
        rows.skip(skip).compact_map do |row|
          next if row.all?(&.empty?)
          text_at = ->(index : Int32?) { index ? row[index - 1]?.to_s.strip : "" }
          day = parse_date(text_at.call(column.call("date")), @dossier.text(format, "format_date"))
          unless day
            @dossier.error(@dossier.relative(file), "date illisible : « #{text_at.call(column.call("date"))} »")
            next
          end
          amount = if index = column.call("montant")
                     number(text_at.call(index), decimal)
                   else
                     number(text_at.call(column.call("credit")), decimal) - number(text_at.call(column.call("debit")), decimal)
                   end
          amount = -amount if format["inverser"]?.try(&.raw) == true
          {day, text_at.call(column.call("libelle")), amount}
        end
      rescue ex : CSV::MalformedCSVError
        @dossier.error(@dossier.relative(file), "CSV illisible : #{ex.message}")
        nil
      end

      private def parse_date(text : String, format : String?) : Time?
        if format == "yyyy-mm-dd"
          Time.parse_utc(text, "%Y-%m-%d")
        else
          Time.parse_utc(text, "%d/%m/%Y")
        end
      rescue Time::Format::Error
        nil
      end

      private def number(text : String, decimal : Char) : BigDecimal
        return BigDecimal.new(0) if text.empty?
        cleaned = text.delete(' ')
        cleaned = cleaned.delete('.').tr(",", ".") if decimal == ','
        BigDecimal.new(cleaned)
      rescue InvalidBigDecimalException
        BigDecimal.new(0)
      end

      # Contrepartie de la première règle qui s'applique, dans l'ordre de
      # l'extension : position, montant donné, libellé le plus long.
      private def categorize(label : String, amount : BigDecimal, rules : Array(YAML::Any)) : String?
        haystack = normalize(label)
        ordered = rules.sort_by do |rule|
          {rule["position"]?.try(&.as_i?) || 100, rule["montant"]? ? 0 : 1, -(@dossier.text(rule, "libelle_contient") || "").size}
        end
        rule = ordered.find do |candidate|
          direction = @dossier.text(candidate, "sens") || "any"
          next false if direction == "in" && amount <= 0
          next false if direction == "out" && amount > 0
          if expected = @dossier.text(candidate, "montant")
            next false unless @dossier.amount(expected) == amount.abs
          end
          haystack.includes?(normalize(@dossier.text(candidate, "libelle_contient") || ""))
        end
        rule.try { |found| @dossier.text(found, "compte").presence || @dossier.text(found, "tiers") }
      end

      private def normalize(text : String) : String
        text.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").upcase.gsub(/\s+/, " ").strip
      end
    end
  end
end
