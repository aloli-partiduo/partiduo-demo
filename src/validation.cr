# SPDX-License-Identifier: AGPL-3.0-or-later

# Validateur léger des dossiers de démonstration (doc/format-dossiers.adoc) :
# schéma, références entre fichiers, écritures équilibrées, relevés,
# cohérence des résultats attendus avec les opérations déclarées, aucun
# identifiant ni secret. Ne dépend ni de Partiduo ni de Marten : la
# bibliothèque standard de Crystal suffit.
require "./validation/dates"
require "./validation/schema"
require "./validation/checker"
require "./validation/dossier"
require "./validation/references"
require "./validation/statements"
require "./validation/secrets"
require "./validation/expectations"

module PartiduoDemo
  # Lue à la compilation dans `shard.yml`, seule source du numéro : chaque
  # commit y incrémente le dernier chiffre.
  VERSION = {{
              (read_file("#{__DIR__}/../shard.yml")
                .lines
                .find(&.starts_with?("version:")) || "version: 0.0.0")
                .gsub(/^version:\s*/, "")
                .chomp
            }}

  module Validation
    # Valide les dossiers de `source` (tous, ou ceux de `codes`) pour un
    # chargement au jour `today` ; rend les contrôles par dossier.
    def self.run(source : String, codes : Array(String), today : Time) : Array(DossierCheck)
      codes = Dir.children(source).select { |name| File.directory?(File.join(source, name)) }.sort! if codes.empty?
      codes.map do |code|
        check = DossierCheck.new(File.join(source, code), today)
        if Dir.exists?(check.directory)
          check.run
        else
          check.error(code, "dossier introuvable dans #{source}")
        end
        check
      end
    end
  end
end
