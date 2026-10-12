# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDemo
  module Validation
    # Aucun identifiant ni secret dans les fichiers d'un dossier : les mots
    # de passe de test sont générés au chargement, les services externes
    # sont simulés et fournissent leurs propres identifiants.
    class Secrets
      # Clés réservées aux secrets et identifiants de connexion.
      KEYS = /passe|password|secret|token|jeton|api_?key|cle_api|identifiant|login|credential/i
      # Valeurs qui ressemblent à un secret : clé privée, mot de passe de
      # test, longue chaîne sans espace.
      VALUES = [
        /-----BEGIN/,
        /\ADemo-[A-Za-z0-9]{8}-[A-Za-z0-9]{6}7\z/,
        /\A[A-Za-z0-9+\/=_\-]{32,}\z/,
      ]
      EMAIL = /[^\s@";]+@[^\s@";]+/

      def initialize(@dossier : DossierCheck)
      end

      def run : Nil
        @dossier.files.each { |name, node| walk(node, name) }
        Dir.glob(File.join(@dossier.directory, "**", "*")).sort.each do |path|
          next if File.directory?(path) || path.ends_with?(".yml")
          name = path.lchop(@dossier.directory + "/")
          File.read(path).each_line.with_index { |line, index| value(line, "#{name}:#{index + 1}") }
        end
      end

      private def walk(node : YAML::Any, where : String) : Nil
        if hash = node.as_h?
          hash.each do |key, child|
            name = key.as_s? || key.raw.to_s
            @dossier.error(@dossier.relative(where), "clé « #{name} » réservée aux secrets : interdite") if KEYS.matches?(name)
            walk(child, "#{where} #{name}")
          end
        elsif list = node.as_a?
          list.each { |child| walk(child, where) }
        elsif text = node.as_s?
          value(text, where)
        end
      end

      private def value(text : String, where : String) : Nil
        text.split(/[;,\s]+/).each do |word|
          if VALUES.any?(&.matches?(word))
            @dossier.error(@dossier.relative(where), "valeur qui ressemble à un secret : « #{word[0, 12]}… »")
          end
        end
        text.scan(EMAIL).each do |match|
          address = match[0]
          unless address.ends_with?(".test")
            @dossier.error(@dossier.relative(where), "adresse « #{address} » : domaine fictif en .test attendu")
          end
        end
      end
    end
  end
end
