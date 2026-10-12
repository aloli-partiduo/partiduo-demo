# SPDX-License-Identifier: AGPL-3.0-or-later

require "spec"
require "file_utils"
require "../src/validation"

# Le validateur des dossiers : les dossiers versionnés passent, et chaque
# défaut qu'il doit trouver est trouvé sur une copie altérée.
private TODAY   = Time.utc(2026, 10, 12)
private SOURCES = File.expand_path("../dossiers", __DIR__)

# Copie d'un dossier dans un répertoire temporaire, `fichier` modifié par
# le bloc, puis validé.
private def altered(code : String, file : String, & : String -> String) : PartiduoDemo::Validation::DossierCheck
  root = File.join(Dir.tempdir, "partiduo-demo-validation-#{Random::Secure.hex(4)}")
  begin
    Dir.mkdir_p(root)
    FileUtils.cp_r(File.join(SOURCES, code), File.join(root, code))
    path = File.join(root, code, file)
    File.write(path, yield File.read(path))
    PartiduoDemo::Validation.run(root, [code], TODAY).first
  ensure
    FileUtils.rm_rf(root)
  end
end

private def errors_of(check : PartiduoDemo::Validation::DossierCheck) : String
  check.errors.join("\n")
end

describe PartiduoDemo::Validation do
  it "valide les quatre dossiers versionnés et recalcule leurs grands totaux" do
    checks = PartiduoDemo::Validation.run(SOURCES, Array(String).new, TODAY)
    checks.map(&.code).should eq(%w[atelier foyer liberal micro])
    checks.each(&.errors.should(eq([] of String)))
    notes = checks.flat_map(&.notes).join("\n")
    notes.should contain("atelier/attendus.yml : controles[3] (solde_comptes) : montant recalculé : 141156.00")
    notes.should contain("atelier/attendus.yml : controles[4] (solde_comptes) : montant recalculé : 28231.20")
    notes.should contain("atelier/attendus.yml : controles[6] (factures) : nombre recalculé : 54")
  end

  it "reste conforme quel que soit le jour du chargement, à partir de février" do
    [Time.utc(2027, 2, 1), Time.utc(2027, 3, 1), Time.utc(2027, 7, 14)].each do |day|
      PartiduoDemo::Validation.run(SOURCES, Array(String).new, day).each(&.errors.should(eq([] of String)))
    end
  end

  it "refuse un montant flottant, un champ inconnu et une date illisible" do
    check = altered("micro", "operations.yml") do |text|
      text.sub(%(montant: "320"), "montant: 320.5").sub("moyen: card", "moyen: card\n    remise: oui").sub("date: N-1-01-05", "date: N-1-13-05")
    end
    errors_of(check).should contain("flottant interdit")
    errors_of(check).should contain("champ inconnu « remise »")
    errors_of(check).should contain("date invalide : « N-1-13-05 »")
  end

  it "refuse une écriture déséquilibrée" do
    check = altered("foyer", "operations.yml", &.sub(%(debit: "245000.00"), %(debit: "245000.01")))
    errors_of(check).should contain("écriture déséquilibrée")
  end

  it "refuse une référence inconnue entre fichiers" do
    check = altered("atelier", "operations.yml", &.sub("client: CLI-MOREAU", "client: CLI-INCONNU"))
    errors_of(check).should contain("client CLI-INCONNU absent du référentiel")
  end

  it "refuse un total attendu incohérent avec les opérations déclarées" do
    check = altered("atelier", "attendus.yml", &.sub(%("141156.00"), %("141157.00")))
    errors_of(check).should contain("montant attendu 141157.00, recalculé 141156.00")
    check = altered("liberal", "attendus.yml", &.sub("etat: locked", "etat: open"))
    errors_of(check).should contain("etat attendu open, recalculé locked")
  end

  it "refuse un identifiant, un secret ou une adresse réelle" do
    check = altered("micro", "parametres.yml", &.sub("urssaf: {plateforme: simulee}", "urssaf: {plateforme: simulee, mot_de_passe: x}"))
    errors_of(check).should contain("réservée aux secrets")
    check = altered("micro", "dossier.yml", &.sub("nicolas@micro.demo.test", "nicolas@exemple.fr"))
    errors_of(check).should contain("adresse fictive en .test")
    check = altered("micro", "dossier.yml", &.sub(%(description: "), %(description: "Demo-Abcd1234-Xyz9ab7 )))
    errors_of(check).should contain("ressemble à un secret")
  end

  it "refuse un relevé dont une ligne n'a pas de règle ou dont les soldes ne se suivent pas" do
    check = altered("foyer", "releves/courant-n-1-03.csv", &.sub("CB CINEMA LES CARMES", "CB BOUTIQUE INCONNUE"))
    errors_of(check).should contain("« CB BOUTIQUE INCONNUE » : aucune règle de catégorisation ne s'applique")
    check = altered("foyer", "releves/courant-n-1-03.csv", &.sub(";23,80;", ";23,90;"))
    errors_of(check).should contain("≠ solde de fin")
  end

  it "refuse un module d'entreprise dans un foyer" do
    check = altered("foyer", "dossier.yml", &.sub("modules: [accounting]", "modules: [accounting, invoicing]"))
    errors_of(check).should contain("modules d'entreprise refusés dans un foyer : invoicing")
  end
end
