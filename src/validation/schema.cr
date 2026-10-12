# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDemo
  module Validation
    # Schéma du format 1 (doc/format-dossiers.adoc) : pour chaque structure,
    # ses champs et leur type ; `!` marque un champ obligatoire.
    #
    # Types : `texte`, `code`, `montant` (chaîne décimale), `entier`,
    # `quantite` (entier ou chaîne décimale), `bool`, `date`, `periode`,
    # `annee`, `courriel`, `siren`, `siret`, `compte`, `couleur`,
    # `[texte]` (liste), `[annee]`, `enum:a|b`, `@structure`,
    # `@structure[]` (liste), `operations` (liste d'opérations).
    module Schema
      alias Fields = Hash(String, String)

      STRUCTURES = {
        "dossier" => {
          "format" => "entier!", "code" => "code!", "profil" => "enum:entreprise|micro|liberal|foyer!",
          "type" => "enum:company|household", "description" => "texte", "societe" => "@societe!",
          "modules" => "[texte]!", "extensions" => "[texte]", "exercices" => "[annee]",
          "utilisateurs" => "@utilisateur[]!", "parcours" => "[texte]",
        },
        "societe" => {
          "nom" => "texte!", "forme_juridique" => "texte", "capital" => "montant", "rcs" => "texte", "siren" => "siren",
          "tva" => "texte", "rue" => "texte", "numero" => "texte", "code_postal" => "texte", "ville" => "texte",
          "pays" => "code", "telephone" => "texte", "courriel" => "courriel", "regime" => "enum:fr|be", "langue" => "enum:fr|en|nl",
        },
        "utilisateur" => {
          "email" => "courriel!", "prenom" => "texte!", "nom" => "texte!", "profil" => "enum:ADMIN|ACCOUNTANT",
          "role" => "enum:member|accountant",
        },
        "referentiel" => {
          "format" => "entier!", "comptes" => "@compte[]", "taux_tva" => "@taux[]", "tiers" => "@tiers[]",
          "articles" => "@article[]", "analytique" => "@analytique", "stock" => "@stock",
        },
        "compte" => {"numero" => "compte!", "libelle" => "texte!", "parent" => "compte!"},
        "taux"   => {"code" => "code!", "libelle" => "texte!", "taux" => "montant!", "categorie" => "code!", "exoneration_code" => "texte", "exoneration_motif" => "texte"},
        "tiers"  => {
          "code" => "code!", "categorie" => "enum:client|fournisseur!", "nom" => "texte",
          "nature" => "enum:individual|business|public", "siren" => "siren", "siret" => "siret", "tva" => "texte",
          "courriel" => "courriel", "adresse" => "@adresse", "personne" => "@personne", "facturation" => "@facturation",
        },
        "adresse"     => {"ligne1" => "texte!", "code_postal" => "texte!", "ville" => "texte!", "pays" => "code"},
        "personne"    => {"nom" => "texte!", "prenoms" => "texte!", "naissance" => "date", "description" => "texte"},
        "facturation" => {"rythme" => "enum:monthly!", "encours_max" => "montant"},
        "article"     => {
          "code" => "code!", "categorie" => "enum:vente|achat!", "nom" => "texte!", "unite" => "code",
          "prix_vente" => "montant", "prix_achat" => "montant", "taux" => "code", "compte" => "compte", "stock" => "bool",
          "poste" => "code", "nature_micro" => "code",
        },
        "analytique"  => {"plans" => "@plan[]", "cles" => "@cle[]"},
        "plan"        => {"nom" => "texte!", "description" => "texte", "postes" => "@poste[]!"},
        "poste"       => {"code" => "code!", "description" => "texte"},
        "cle"         => {"nom" => "texte!", "description" => "texte", "journaux" => "[texte]", "repartition" => "@repartition[]!"},
        "repartition" => {"pourcentage" => "montant!", "postes" => "[texte]!"},
        "stock"       => {"depots" => "@depot[]"},
        "depot"       => {"nom" => "texte!", "adresse" => "texte", "ville" => "texte", "pays" => "code", "telephone" => "texte", "defaut" => "bool"},
        "parametres"  => {
          "format" => "entier!", "comptabilite" => "@comptabilite", "facturation" => "@param_facturation",
          "analytique" => "@param_analytique", "micro" => "@param_micro", "liberal" => "@param_liberal",
          "einv" => "@plateforme", "choruspro" => "@plateforme", "teledec" => "@teledec", "urssaf" => "@plateforme",
          "bankimport" => "@bankimport",
        },
        "comptabilite"      => {"journal_achats" => "@journal_achats"},
        "journal_achats"    => {"compte_defaut" => "compte!"},
        "param_facturation" => {
          "tva_sur_debits" => "bool", "iban" => "texte", "bic" => "texte", "courriel_expediteur" => "courriel",
          "nom_expediteur" => "texte", "taux_penalites" => "montant", "categorie_operation" => "enum:goods|services|mixed",
          "delai_paiement" => "entier", "envoi_automatique" => "bool",
        },
        "param_analytique" => {"ventilation_ventes" => "bool"},
        "param_micro"      => {"periodicite" => "enum:monthly|quarterly!", "debut_activite" => "date!", "nature_defaut" => "code!"},
        "param_liberal"    => {"profession" => "texte!", "debut_activite" => "date!", "rubrique_defaut" => "code!"},
        "plateforme"       => {"plateforme" => "enum:simulee!", "profil" => "code"},
        "teledec"          => {
          "plateforme" => "enum:simulee!", "regime" => "code!", "tva" => "code!", "courriel" => "courriel!", "siret" => "siret!",
        },
        "bankimport" => {"formats" => "@format_csv[]", "regles" => "@regle[]"},
        "format_csv" => {
          "nom" => "texte!", "etablissement" => "texte", "journal" => "enum:banque", "compte" => "compte!",
          "separateur" => "enum:comma|semicolon|tab|pipe", "encodage" => "enum:utf-8|windows-1252",
          "lignes_entete" => "entier", "format_date" => "enum:dd/mm/yyyy|yyyy-mm-dd", "separateur_decimal" => "enum:comma|dot",
          "separateur_milliers" => "enum:none|space|dot|comma|apostrophe", "inverser" => "bool", "colonnes" => "@colonnes!",
        },
        "colonnes" => {
          "date" => "entier!", "libelle" => "entier!", "montant" => "entier", "debit" => "entier", "credit" => "entier",
          "information" => "entier", "reference" => "entier", "tiers" => "entier",
        },
        "regle" => {
          "libelle_contient" => "texte", "montant" => "montant", "sens" => "enum:any|in|out", "compte" => "compte",
          "tiers" => "code", "position" => "entier",
        },
        "operations"     => {"format" => "entier!", "operations" => "operations", "recentes" => "operations", "fin" => "operations"},
        "condition"      => {"depuis" => "date", "avant" => "date"},
        "reglement"      => {"delai" => "entier!", "mode" => "enum:banque|encaissement", "moyen" => "enum:card|cash|cheque|transfer", "libelle" => "texte"},
        "delai"          => {"delai" => "entier!"},
        "ligne_ecriture" => {"compte" => "compte!", "debit" => "montant", "credit" => "montant", "tiers" => "code", "libelle" => "texte"},
        "ligne_banque"   => {"compte" => "compte", "tiers" => "code", "montant" => "montant!", "libelle" => "texte"},
        "ligne_stock"    => {"article" => "code!", "quantite" => "quantite!", "cout" => "montant"},
        "ligne_achat"    => {
          "article" => "code", "quantite" => "quantite", "prix" => "montant", "compte" => "compte", "montant" => "montant",
          "taux" => "code", "tva" => "montant", "libelle" => "texte",
        },
        "ligne_vente"      => {"article" => "code!", "quantite" => "quantite!"},
        "ligne_plateforme" => {"libelle" => "texte!", "quantite" => "quantite!", "prix" => "montant!", "unite" => "code"},
        "avoir"            => {"delai" => "entier!", "motif" => "texte!", "categorie" => "enum:goods|services|mixed!", "lignes" => "@ligne_vente[]!"},
        "acceptation"      => {"delai" => "entier!", "acompte" => "montant", "reglement_acompte" => "@reglement", "facture_finale" => "@facture_finale"},
        "facture_finale"   => {"delai" => "entier!", "reglement" => "@reglement"},
        "paiement_tva"     => {"delai" => "entier!", "compte" => "compte!", "libelle" => "texte!"},
        "ligne_image"      => {"libelle" => "texte!", "montant" => "montant!"},
        "image"            => {
          "modele" => "enum:ticket", "enseigne" => "texte!", "adresse" => "texte!", "lignes" => "@ligne_image[]!",
          "tva" => "montant!", "paiement" => "texte!", "couleur" => "couleur!",
        },
        "saisie" => {
          "si" => "@condition", "libelle" => "texte!", "numero" => "texte!", "lignes" => "@ligne_achat[]!", "reglement" => "@reglement",
        },
        "copie_micro" => {
          "enseigne" => "texte!", "adresse" => "texte!", "numero" => "texte!", "libelle" => "texte!", "taux" => "montant!",
          "couleur" => "couleur!",
        },
        "declaration_teledec" => {"nature" => "enum:liasse|das2|vat_ca3!", "exercice" => "annee", "annee" => "annee", "derniere_de" => "annee"},
        "pointage"            => {"reference" => "texte!", "solde_debut" => "montant", "solde_fin" => "montant"},
        "element_prevision"   => {"libelle" => "texte!", "formule" => "texte!", "montant" => "montant!"},
        "categorie_prevision" => {"libelle" => "texte!", "elements" => "@element_prevision[]!"},
        "crm"                 => {
          "format" => "entier!", "organisations" => "@organisation[]", "contacts" => "@contact[]",
          "opportunites" => "@opportunite[]", "activites" => "@activite[]",
        },
        "organisation" => {
          "ref" => "code!", "nom" => "texte!", "nature" => "enum:business|public|individual!", "siren" => "texte",
          "ville" => "texte", "pays" => "code", "origine" => "code!", "responsable" => "courriel",
        },
        "contact" => {
          "ref" => "code!", "organisation" => "code", "civilite" => "enum:mr|ms", "prenom" => "texte", "nom" => "texte!",
          "fonction" => "texte", "courriel" => "courriel", "base_legale" => "code", "origine" => "code", "opposition" => "texte",
        },
        "perte"       => {"motif" => "code!", "commentaire" => "texte"},
        "opportunite" => {
          "ref" => "code", "titre" => "texte!", "organisation" => "code!", "contact" => "code", "montant" => "montant!",
          "etape" => "enum:discovery|qualification|proposal|negotiation|won|lost!", "responsable" => "courriel",
          "cloture_prevue" => "date!", "origine" => "code", "perte" => "@perte", "devis" => "bool",
        },
        "activite" => {
          "genre" => "enum:call|email|meeting|task|note!", "objet" => "texte!", "echeance" => "date!", "responsable" => "courriel",
          "opportunite" => "code", "organisation" => "code",
        },
        "attendus" => {"format" => "entier!", "controles" => "@controle[]!"},
        "controle" => {
          "type" => "code!", "exercice" => "annee", "prefixe" => "compte", "sens" => "enum:debit|credit",
          "journaux" => "enum:ventes|achats", "montant" => "montant", "formulaire" => "code", "nombre" => "entier",
          "statut" => "code", "minimum" => "entier", "natures" => "[texte]", "frais" => "montant", "recettes" => "montant",
          "achats" => "montant", "depenses" => "montant", "payees" => "bool", "etat" => "code", "comptabilisees" => "bool",
        },
      } of String => Fields

      # Champs communs à toutes les opérations.
      COMMON = {"type" => "code!", "date" => "date", "si" => "@condition", "ref" => "code"}

      # Champs propres à chaque type d'opération.
      OPERATIONS = {
        "ecriture"        => {"journal" => "enum:banque|divers|achats|ventes", "libelle" => "texte!", "piece" => "texte", "lignes" => "@ligne_ecriture[]!"},
        "banque"          => {"journal" => "enum:banque", "lignes" => "@ligne_banque[]!"},
        "inventaire"      => {"libelle" => "texte!", "lignes" => "@ligne_stock[]!"},
        "mouvement_stock" => {"libelle" => "texte!", "lignes" => "@ligne_stock[]!"},
        "achat"           => {
          "fournisseur" => "code!", "numero" => "texte!", "libelle" => "texte!", "lignes" => "@ligne_achat[]!", "copie" => "bool",
          "ventilation" => "bool", "reglement" => "@reglement",
        },
        "facture_plateforme" => {
          "fournisseur" => "code!", "numero" => "texte!", "libelle" => "texte!", "note" => "texte", "taux" => "montant!",
          "lignes" => "@ligne_plateforme[]!", "comptabiliser" => "@condition", "reglement" => "@reglement",
        },
        "facture" => {
          "client" => "code!", "objet" => "texte", "categorie" => "enum:goods|services|mixed!", "reference_commande" => "texte",
          "chorus_pro" => "bool", "lignes" => "@ligne_vente[]!", "avoir" => "@avoir", "reglement" => "@reglement",
        },
        "bon_de_livraison" => {"client" => "code!", "notes" => "texte", "categorie" => "enum:goods|services|mixed!", "lignes" => "@ligne_vente[]!"},
        "bon_de_retour"    => {
          "bon" => "code!", "motif" => "code!", "notes" => "texte", "categorie" => "enum:goods|services|mixed!",
          "lignes" => "@ligne_vente[]!",
        },
        "devis" => {
          "client" => "code!", "objet" => "texte", "categorie" => "enum:goods|services|mixed!", "lignes" => "@ligne_vente[]!",
          "acceptation" => "@acceptation", "refus" => "@delai",
        },
        "fin_de_mois"     => {} of String => String,
        "recapitulatives" => {"reglement" => "@reglement"},
        "declaration_tva" => {
          "formulaire" => "code!", "periodicite" => "enum:month|quarter", "periode" => "periode!", "journal" => "enum:divers",
          "paiement" => "@paiement_tva",
        },
        "rapprochement" => {"journal" => "enum:banque", "mois" => "periode!"},
        "justificatif"  => {
          "fichier" => "texte!", "source" => "enum:photo|file", "genre" => "code", "fournisseur" => "code",
          "nom_fournisseur" => "texte!", "montant" => "montant!", "reference" => "texte", "image" => "@image!", "saisie" => "@saisie",
        },
        "micro_recette" => {"nature" => "code!", "montant" => "montant!", "moyen" => "enum:card|cash|cheque|transfer!", "tiers" => "texte", "libelle" => "texte!"},
        "micro_achat"   => {
          "nature" => "code!", "montant" => "montant!", "moyen" => "enum:card|cash|cheque|transfer!", "fournisseur" => "code",
          "tiers" => "texte", "libelle" => "texte!", "reference" => "texte", "copie" => "@copie_micro",
        },
        "urssaf_mandat"      => {"iban" => "texte!", "bic" => "texte!", "titulaire" => "texte!"},
        "urssaf_declaration" => {"periode" => "periode!", "paiement" => "bool"},
        "liberal_recette"    => {"montant" => "montant!", "libelle" => "texte!", "moyen" => "enum:card|cash|cheque|transfer", "tiers" => "texte"},
        "liberal_depense"    => {
          "rubrique" => "code!", "montant" => "montant!", "libelle" => "texte!", "tiers" => "texte", "part_privee" => "montant",
          "moyen" => "enum:card|cash|cheque|transfer",
        },
        "liberal_immobilisation" => {
          "libelle" => "texte!", "categorie" => "code!", "montant" => "montant!", "duree" => "entier!",
          "moyen" => "enum:card|cash|cheque|transfer", "tiers" => "texte",
        },
        "liberal_cloture" => {"exercice" => "annee!"},
        "rejet_reglement" => {
          "clients" => "[texte]!", "motif" => "code!", "texte" => "texte", "frais" => "montant", "refacturer" => "bool",
          "taux_frais" => "code",
        },
        "relances"                   => {"envoyer" => "entier"},
        "synchronisation_plateforme" => {} of String => String,
        "teledeclarations"           => {"declarations" => "@declaration_teledec[]!"},
        "crm"                        => {"fichier" => "texte!"},
        "modeles"                    => {"langue" => "enum:fr|en|nl", "defaut" => "enum:asciidoc|markdown|odt|docx", "rendre_derniere_facture" => "bool"},
        "import_releve"              => {
          "journal" => "enum:banque", "fichier" => "texte!", "format" => "texte", "transferer" => "bool", "pointage" => "@pointage",
        },
        "prevision" => {"nom" => "texte!", "debut" => "periode!", "fin" => "periode!", "categories" => "@categorie_prevision[]!"},
      } of String => Fields
    end
  end
end
