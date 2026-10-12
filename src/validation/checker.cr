# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDemo
  module Validation
    # Contrôle d'un nœud YAML contre le schéma : champs connus, champs
    # obligatoires, types. Les erreurs citent le fichier et le chemin.
    class Checker
      AMOUNT   = /\A-?\d+(\.\d{1,4})?\z/
      CODE     = /\A[A-Za-z0-9][A-Za-z0-9_.+\-]*\z/
      ACCOUNT  = /\A\d{1,12}\z/
      EMAIL    = /\A[^@\s]+@[^@\s]+\.test\z/
      SIREN    = /\A\d{3} ?\d{3} ?\d{3}\z/
      SIRET    = /\A\d{14}\z/
      LIST     = /\A\[(\w+)\]\z/
      ENUM     = /\Aenum:(.+)\z/
      INTEGERS = %w[entier]

      getter errors : Array(String)

      def initialize(@errors : Array(String))
      end

      def check(node : YAML::Any, structure : String, where : String) : Nil
        fields = Schema::STRUCTURES[structure]? || raise ArgumentError.new("structure inconnue : #{structure}")
        check_fields(node, fields, where)
      end

      def check_fields(node : YAML::Any, fields : Schema::Fields, where : String) : Nil
        hash = node.as_h?
        return error(where, "table attendue") unless hash
        hash.each_key do |key|
          name = key.as_s? || next error(where, "clé non textuelle : #{key}")
          error(where, "champ inconnu « #{name} »") unless fields.has_key?(name)
        end
        fields.each do |name, spec|
          required = spec.ends_with?('!')
          type = spec.rchop('!')
          value = hash[YAML::Any.new(name)]?
          if value.nil? || value.raw.nil?
            error(where, "champ obligatoire « #{name} » absent") if required
            next
          end
          check_value(value, type, "#{where}.#{name}")
        end
      end

      def check_value(value : YAML::Any, type : String, where : String) : Nil
        if match = ENUM.match(type)
          allowed = match[1].split('|')
          text = value.as_s?
          error(where, "valeur parmi #{allowed.join(", ")} attendue (« #{value.raw} »)") unless text && allowed.includes?(text)
        elsif match = LIST.match(type)
          list = value.as_a? || return error(where, "liste attendue")
          list.each_with_index { |item, index| check_value(item, match[1], "#{where}[#{index}]") }
        elsif type.starts_with?('@')
          name = type.lchop('@')
          if name.ends_with?("[]")
            list = value.as_a? || return error(where, "liste attendue")
            list.each_with_index { |item, index| check(item, name.rchop("[]"), "#{where}[#{index}]") }
          else
            check(value, name, where)
          end
        elsif type == "operations"
          list = value.as_a? || return error(where, "liste attendue")
          list.each_with_index { |item, index| check_operation(item, "#{where}[#{index}]") }
        else
          check_scalar(value, type, where)
        end
      end

      def check_operation(node : YAML::Any, where : String) : Nil
        type = node["type"]?.try(&.as_s?)
        return error(where, "opération sans type") unless type
        fields = Schema::OPERATIONS[type]? || return error(where, "type d'opération inconnu « #{type} »")
        check_fields(node, Schema::COMMON.merge(fields), "#{where} (#{type})")
      end

      private def check_scalar(value : YAML::Any, type : String, where : String) : Nil
        raw = value.raw
        case type
        when "entier"
          error(where, "entier attendu") unless raw.is_a?(Int64)
        when "bool"
          error(where, "true ou false attendu") unless raw.is_a?(Bool)
        when "quantite"
          ok = raw.is_a?(Int64) || (raw.is_a?(String) && AMOUNT.matches?(raw))
          error(where, "quantité entière ou chaîne décimale attendue (« #{raw} »)") unless ok
        when "couleur"
          list = value.as_a?
          ok = list && list.size == 3 && list.all? { |item| (item.raw.as?(Int64) || -1).in?(0..255) }
          error(where, "trois entiers de 0 à 255 attendus") unless ok
        else
          text = raw.as?(String)
          return error(where, scalar_hint(raw, type)) unless text
          check_text(text, type, where)
        end
      end

      private def scalar_hint(raw, type : String) : String
        case raw
        when Float64 then "flottant interdit : chaîne décimale entre guillemets attendue (#{type})"
        when Int64   then "nombre non textuel : chaîne entre guillemets attendue (#{type})"
        when Time    then "date absolue non textuelle : à écrire entre guillemets"
        else              "texte attendu (#{type})"
        end
      end

      private def check_text(text : String, type : String, where : String) : Nil
        valid = case type
                when "texte"    then true
                when "montant"  then AMOUNT.matches?(text)
                when "code"     then CODE.matches?(text)
                when "compte"   then ACCOUNT.matches?(text)
                when "courriel" then EMAIL.matches?(text)
                when "siren"    then SIREN.matches?(text) && luhn?(text.delete(' '))
                when "siret"    then SIRET.matches?(text) && luhn?(text)
                when "date"     then Dates.date?(text)
                when "periode"  then Dates.period?(text)
                when "annee"    then Dates.year?(text)
                else                 raise ArgumentError.new("type inconnu : #{type}")
                end
        error(where, "#{type} invalide : « #{text} »#{hint(type)}") unless valid
        unknown = Dates.unknown_tokens(text)
        error(where, "jeton inconnu #{unknown.join(", ")}") unless unknown.empty?
      end

      private def hint(type : String) : String
        case type
        when "montant"  then " (chaîne décimale, point décimal)"
        when "courriel" then " (adresse fictive en .test)"
        when "siren"    then " (clé de Luhn)"
        when "siret"    then " (clé de Luhn)"
        else                 ""
        end
      end

      # Clé de Luhn d'un SIREN ou d'un SIRET.
      def luhn?(digits : String) : Bool
        sum = digits.reverse.each_char.with_index.sum do |(char, index)|
          value = char.to_i
          value *= 2 if index.odd?
          value > 9 ? value - 9 : value
        end
        sum % 10 == 0
      end

      def error(where : String, message : String) : Nil
        @errors << "#{where} : #{message}"
      end
    end
  end
end
