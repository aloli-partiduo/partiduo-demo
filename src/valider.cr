# SPDX-License-Identifier: AGPL-3.0-or-later

# `bin/partiduo-demo-valider [--detail] [--jour=AAAA-MM-JJ] [RÉPERTOIRE] [DOSSIER…]` :
# valide les dossiers de démonstration (par défaut `dossiers/`, tous) ; code
# de sortie non nul à la première erreur trouvée.
require "option_parser"
require "./validation"

source = "dossiers"
detail = false
today = Time.utc(Time.local.year, Time.local.month, Time.local.day)
codes = [] of String
OptionParser.parse do |parser|
  parser.banner = "Usage : partiduo-demo-valider [--detail] [--jour=AAAA-MM-JJ] [RÉPERTOIRE] [DOSSIER…]"
  parser.on("--detail", "affiche aussi les contrôles recalculés") { detail = true }
  parser.on("--jour=AAAA-MM-JJ", "jour de chargement simulé (défaut : aujourd'hui)") do |value|
    today = Time.parse_utc(value, "%Y-%m-%d")
  end
  parser.on("-h", "--help", "cette aide") do
    puts parser
    exit 0
  end
  parser.unknown_args do |arguments|
    if first = arguments.first?
      source = first
      codes = arguments[1..]
    end
  end
end

abort "Répertoire introuvable : #{source}" unless Dir.exists?(source)
checks = PartiduoDemo::Validation.run(source, codes, today)
failed = 0
checks.each do |check|
  if check.errors.empty?
    puts "ok     #{check.code} (#{check.notes.size} contrôles attendus examinés)"
  else
    failed += 1
    puts "ERREUR #{check.code} : #{check.errors.size} erreur(s)"
    check.errors.each { |error| puts "  - #{error}" }
  end
  check.notes.each { |note| puts "    · #{note}" } if detail
end
exit(failed > 0 ? 1 : 0)
