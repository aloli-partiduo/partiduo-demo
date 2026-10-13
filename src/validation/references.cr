# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDemo
  module Validation
    # Références entre fichiers : tiers, articles, postes, taux, modules et
    # extensions exigés par chaque opération, documents nommés (`ref`),
    # utilisateurs, fichiers cités ; écritures équilibrées.
    class References
      # Module ou extension exigé par un type d'opération.
      REQUIRES = {
        "ecriture" => "accounting", "banque" => "accounting", "achat" => "accounting", "declaration_tva" => "accounting",
        "rapprochement" => "accounting", "prevision" => "accounting", "inventaire" => "stock", "mouvement_stock" => "stock",
        "facture" => "invoicing", "bon_de_livraison" => "invoicing", "bon_de_retour" => "invoicing", "devis" => "invoicing",
        "fin_de_mois" => "invoicing", "recapitulatives" => "invoicing", "rejet_reglement" => "invoicing",
        "relances" => "invoicing", "facture_plateforme" => "einv", "synchronisation_plateforme" => "einv",
        "justificatif" => "document", "micro_recette" => "micro", "micro_achat" => "micro", "urssaf_mandat" => "urssaf",
        "urssaf_declaration" => "urssaf", "liberal_recette" => "liberal", "liberal_depense" => "liberal",
        "liberal_immobilisation" => "liberal", "liberal_cloture" => "liberal", "teledeclarations" => "teledec",
        "crm" => "crm", "modeles" => "modeles", "import_releve" => "bankimport", "perso_emprunt" => "perso",
        "perso_recurrente" => "perso", "perso_valorisation" => "perso", "perso_budget" => "perso",
        "perso_deplacements" => "perso", "perso_operation" => "perso",
      }

      # Compte du foyer repris d'office au provisionnement d'un dossier foyer
      # avec PERSO : le journal financier du plan réduit.
      PERSO_CURRENT_ACCOUNT = "Compte courant"

      # Modules d'entreprise refusés dans un foyer (ADR-011 A3).
      HOUSEHOLD_EXCLUDED = %w[invoicing micro liberal stock followup analytic]

      # Sections de `parametres.yml` et extension ou module qu'elles exigent.
      PARAMETERS = {
        "facturation" => "invoicing", "analytique" => "analytic", "micro" => "micro", "liberal" => "liberal",
        "einv" => "einv", "choruspro" => "choruspro", "teledec" => "teledec", "urssaf" => "urssaf", "bankimport" => "bankimport",
        "comptabilite" => "accounting", "perso" => "perso",
      }

      @refs = {} of String => String
      @emails = Set(String).new

      def initialize(@dossier : DossierCheck)
      end

      def run : Nil
        components
        reference_data
        @dossier.list(@dossier.identity, "utilisateurs").each { |user| @dossier.text(user, "email").try { |email| @emails << email } }
        @dossier.operations.each { |(where, operation)| operation(where, operation) }
      end

      private def components : Nil
        identity = @dossier.identity
        modules = @dossier.list(identity, "modules").compact_map(&.as_s?)
        extensions = @dossier.list(identity, "extensions").compact_map(&.as_s?)
        @active = (modules + extensions).to_set
        if @dossier.text(identity, "type") == "household"
          refused = modules & HOUSEHOLD_EXCLUDED
          error("dossier.yml", "modules d'entreprise refusés dans un foyer : #{refused.join(", ")}") unless refused.empty?
          error("dossier.yml", "un foyer exige le module accounting") unless modules.includes?("accounting")
        end
        @dossier.parameters.as_h?.try &.each_key do |key|
          name = key.as_s? || next
          needed = PARAMETERS[name]? || next
          error("parametres.yml", "section « #{name} » sans « #{needed} » dans dossier.yml") unless active?(needed)
        end
      end

      @active = Set(String).new

      private def active?(code : String) : Bool
        @active.includes?(code)
      end

      private def reference_data : Nil
        reference = @dossier.reference
        unique(@dossier.list(reference, "comptes"), "numero", "referentiel.yml : comptes")
        unique(@dossier.list(reference, "tiers"), "code", "referentiel.yml : tiers")
        unique(@dossier.list(reference, "articles"), "code", "referentiel.yml : articles")
        unique(@dossier.list(@dossier.identity, "utilisateurs"), "email", "dossier.yml : utilisateurs")
        posts = analytic_posts
        @dossier.items.each do |code, item|
          rate = @dossier.text(item, "taux")
          error("referentiel.yml", "article #{code} : taux #{rate} inconnu") if rate && !@dossier.rates.has_key?(rate)
          post = @dossier.text(item, "poste")
          error("referentiel.yml", "article #{code} : poste analytique #{post} inconnu") if post && !posts.includes?(post)
          if item["stock"]?.try(&.raw) == true && !active?("stock")
            error("referentiel.yml", "article #{code} suivi en stock sans module stock")
          end
          nature = @dossier.text(item, "nature_micro")
          error("referentiel.yml", "article #{code} : nature micro sans module micro") if nature && !active?("micro")
        end
        @dossier.list(@dossier.reference["analytique"]?, "cles").each do |key|
          @dossier.list(key, "repartition").each do |row|
            @dossier.list(row, "postes").each do |post|
              error("referentiel.yml", "clé analytique : poste #{post.as_s?} inconnu") unless posts.includes?(post.as_s?)
            end
          end
          total = @dossier.list(key, "repartition").sum(BigDecimal.new(0)) { |row| @dossier.amount(@dossier.text(row, "pourcentage")) }
          error("referentiel.yml", "clé analytique #{@dossier.text(key, "nom")} : total #{total} % au lieu de 100 %") unless total == 100
        end
        @dossier.list(@dossier.reference, "tiers").each do |party|
          if @dossier.text(party, "categorie") == "fournisseur" && party["facturation"]?
            error("referentiel.yml", "tiers #{@dossier.text(party, "code")} : facturation réservée aux clients")
          end
          if @dossier.text(party, "nom").nil? && party["personne"]?.nil?
            error("referentiel.yml", "tiers #{@dossier.text(party, "code")} : nom ou personne attendu")
          end
        end
        perso_parameters
        formats = @dossier.list(@dossier.parameters["bankimport"]?, "formats")
        formats.each do |format|
          columns = format["colonnes"]?
          amount = columns.try(&.["montant"]?)
          split = columns.try(&.["debit"]?) && columns.try(&.["credit"]?)
          error("parametres.yml", "format #{@dossier.text(format, "nom")} : colonne montant, ou débit et crédit") unless amount || split
        end
      end

      # Membres du foyer parmi les utilisateurs, titulaires parmi les membres,
      # comptes et catégories en un seul exemplaire, parent déclaré avant.
      private def perso_parameters : Nil
        perso = @dossier.parameters["perso"]? || return
        users = @dossier.list(@dossier.identity, "utilisateurs").compact_map { |user| @dossier.text(user, "email") }.to_set
        unique(@dossier.list(perso, "membres"), "email", "parametres.yml : perso.membres")
        unique(@dossier.list(perso, "comptes"), "libelle", "parametres.yml : perso.comptes")
        @dossier.list(perso, "membres").each do |member|
          email = @dossier.text(member, "email") || next
          error("parametres.yml", "membre du foyer #{email} : pas un utilisateur du dossier") unless users.includes?(email)
        end
        @dossier.list(perso, "comptes").each do |account|
          @dossier.list(account, "titulaires").each do |holder|
            unless perso_members.includes?(holder.as_s?)
              error("parametres.yml", "compte #{@dossier.text(account, "libelle")} : titulaire #{holder.as_s?} n'est pas un membre du foyer")
            end
          end
          if (@dossier.text(account, "nature") == "property") != !account["genre"]?.nil?
            error("parametres.yml", "compte #{@dossier.text(account, "libelle")} : genre pour un bien seulement, et obligatoire")
          end
        end
        created = Set(String).new
        @dossier.list(perso, "categories").each do |category|
          label = @dossier.text(category, "libelle") || next
          parent = @dossier.text(category, "parent")
          error("parametres.yml", "catégorie #{label} : parent ou parent_compte, pas les deux") if parent && category["parent_compte"]?
          error("parametres.yml", "catégorie #{label} : parent « #{parent} » non déclaré avant") if parent && !created.includes?(parent)
          created << label
        end
      end

      private def analytic_posts : Set(String)
        posts = Set(String).new
        @dossier.list(@dossier.reference["analytique"]?, "plans").each do |plan|
          @dossier.list(plan, "postes").each { |post| @dossier.text(post, "code").try { |code| posts << code } }
        end
        posts
      end

      private def unique(list : Array(YAML::Any), key : String, where : String) : Nil
        seen = Set(String).new
        list.each do |item|
          value = @dossier.text(item, key) || next
          error(where, "#{key} « #{value} » en double") unless seen.add?(value)
        end
      end

      private def operation(where : String, operation : YAML::Any) : Nil
        type = @dossier.text(operation, "type") || return
        dated = !where.includes?(": fin[")
        if dated && operation["date"]?.nil?
          error(where, "date obligatoire")
        elsif !dated && operation["date"]?
          error(where, "une opération de fin se joue au jour du chargement : pas de date")
        end
        needed = REQUIRES[type]?
        error(where, "exige « #{needed} » dans les modules ou extensions") if needed && !active?(needed)
        @dossier.text(operation, "ref").try do |ref|
          error(where, "ref « #{ref} » en double") if @refs.has_key?(ref)
          @refs[ref] = type
        end
        party(where, operation, "client", "client")
        party(where, operation, "fournisseur", "fournisseur")
        items(where, operation, type)
        rates(where, operation)
        case type
        when "ecriture"        then balanced(where, operation)
        when "bon_de_retour"   then delivery(where, operation)
        when "rejet_reglement" then customers(where, operation)
        when "facture"         then chorus(where, operation)
        when "crm"             then crm(where, operation)
        when "import_releve"   then statement(where, operation)
        when "justificatif"    then receipt(where, operation)
        end
        perso(where, operation) if type.starts_with?("perso_")
      end

      # Opération du foyer : comptes du foyer (déclarés ou le compte courant
      # repris d'office), membres, sens et contrepartie.
      private def perso(where : String, operation : YAML::Any) : Nil
        accounts = perso_accounts
        %w[compte compte_payeur vers].each do |key|
          label = @dossier.text(operation, key) || next
          error(where, "#{key} « #{label} » : pas un compte du foyer") unless accounts.includes?(label)
        end
        @dossier.text(operation, "membre").try do |email|
          error(where, "membre #{email} : pas un membre du foyer") unless perso_members.includes?(email)
        end
        type = @dossier.text(operation, "type")
        return unless type.in?("perso_recurrente", "perso_operation")
        transfer = @dossier.text(operation, "sens") == "transfer"
        if transfer && (operation["vers"]?.nil? || operation["categorie"]?)
          error(where, "virement : vers (compte du foyer) attendu, sans catégorie")
        elsif !transfer && (operation["categorie"]?.nil? || operation["vers"]?)
          error(where, "dépense ou recette : catégorie attendue, sans vers")
        end
      end

      private def perso_accounts : Set(String)
        labels = @dossier.list(@dossier.parameters["perso"]?, "comptes").compact_map { |item| @dossier.text(item, "libelle") }.to_set
        labels << PERSO_CURRENT_ACCOUNT
        labels
      end

      private def perso_members : Set(String)
        @dossier.list(@dossier.parameters["perso"]?, "membres").compact_map { |item| @dossier.text(item, "email") }.to_set
      end

      private def party(where : String, operation : YAML::Any, key : String, category : String) : Nil
        code = @dossier.text(operation, key) || return
        party = @dossier.list(@dossier.reference, "tiers").find { |item| @dossier.text(item, "code") == code }
        if party.nil?
          error(where, "#{key} #{code} absent du référentiel")
        elsif @dossier.text(party, "categorie") != category
          error(where, "#{code} n'est pas un #{category}")
        end
      end

      private def items(where : String, operation : YAML::Any, type : String) : Nil
        lines = @dossier.list(operation, "lignes")
        lines += @dossier.list(operation["avoir"]?, "lignes")
        lines += @dossier.list(operation["saisie"]?, "lignes")
        lines.each do |line|
          code = @dossier.text(line, "article") || next
          item = @dossier.items[code]?
          next error(where, "article #{code} absent du référentiel") unless item
          if type.in?("facture", "devis", "bon_de_livraison", "bon_de_retour") && @dossier.text(item, "categorie") != "vente"
            error(where, "article #{code} : article de vente attendu")
          end
          if type.in?("inventaire", "mouvement_stock") && item["stock"]?.try(&.raw) != true
            error(where, "article #{code} non suivi en stock")
          end
          if type.in?("inventaire") && line["cout"]?.nil?
            error(where, "article #{code} : coût obligatoire à l'inventaire")
          end
        end
        lines.each do |line|
          next unless type.in?("achat", "justificatif")
          has_item = !line["article"]?.nil?
          has_amount = !line["montant"]?.nil?
          error(where, "ligne d'achat : article (quantité, prix) ou montant") unless has_item ^ has_amount
          error(where, "ligne d'achat #{@dossier.text(line, "article")} : quantité et prix attendus") if has_item && !(line["quantite"]? && line["prix"]?)
        end
      end

      private def rates(where : String, operation : YAML::Any) : Nil
        lines = @dossier.list(operation, "lignes") + @dossier.list(operation["saisie"]?, "lignes")
        codes = lines.compact_map { |line| @dossier.text(line, "taux") }
        @dossier.text(operation, "taux_frais").try { |code| codes << code }
        codes.each { |code| error(where, "taux de TVA #{code} inconnu") unless @dossier.rates.has_key?(code) }
      end

      # Écriture équilibrée : chaque ligne au débit ou au crédit, total
      # des débits égal au total des crédits.
      private def balanced(where : String, operation : YAML::Any) : Nil
        debit = BigDecimal.new(0)
        credit = BigDecimal.new(0)
        @dossier.list(operation, "lignes").each do |line|
          has_debit = !line["debit"]?.nil?
          has_credit = !line["credit"]?.nil?
          error(where, "ligne #{@dossier.text(line, "compte")} : débit ou crédit, pas les deux") unless has_debit ^ has_credit
          debit += @dossier.amount(@dossier.text(line, "debit"))
          credit += @dossier.amount(@dossier.text(line, "credit"))
        end
        error(where, "écriture déséquilibrée : débit #{debit}, crédit #{credit}") unless debit == credit
      end

      private def delivery(where : String, operation : YAML::Any) : Nil
        ref = @dossier.text(operation, "bon") || return
        error(where, "bon « #{ref} » : bon_de_livraison nommé attendu avant") unless @refs[ref]? == "bon_de_livraison"
      end

      private def customers(where : String, operation : YAML::Any) : Nil
        @dossier.list(operation, "clients").each do |code|
          party = @dossier.list(@dossier.reference, "tiers").find { |item| @dossier.text(item, "code") == code.as_s? }
          error(where, "client #{code.as_s?} absent du référentiel") unless party && @dossier.text(party, "categorie") == "client"
        end
      end

      private def chorus(where : String, operation : YAML::Any) : Nil
        return unless operation["chorus_pro"]?.try(&.raw) == true
        error(where, "dépôt Chorus Pro sans extension choruspro") unless active?("choruspro")
        code = @dossier.text(operation, "client")
        party = @dossier.list(@dossier.reference, "tiers").find { |item| @dossier.text(item, "code") == code }
        if party && !(@dossier.text(party, "nature") == "public" && party["siret"]?)
          error(where, "dépôt Chorus Pro : client public doté d'un SIRET attendu")
        end
      end

      private def receipt(where : String, operation : YAML::Any) : Nil
        return unless operation["saisie"]?
        error(where, "justificatif saisi : fournisseur attendu") unless operation["fournisseur"]?
        error(where, "justificatif saisi : module accounting attendu") unless active?("accounting")
      end

      private def statement(where : String, operation : YAML::Any) : Nil
        file = @dossier.text(operation, "fichier") || return
        error(where, "relevé #{file} introuvable") unless safe?(file) && File.exists?(File.join(@dossier.directory, file))
        name = @dossier.text(operation, "format")
        perso_parameters
        formats = @dossier.list(@dossier.parameters["bankimport"]?, "formats")
        if name && formats.none? { |format| @dossier.text(format, "nom") == name }
          error(where, "format CSV « #{name} » absent de parametres.yml")
        end
      end

      private def crm(where : String, operation : YAML::Any) : Nil
        file = @dossier.text(operation, "fichier") || return
        return error(where, "fichier #{file} refusé") unless safe?(file)
        node = @dossier.parse(file) || return
        Checker.new(@dossier.errors).check(node, "crm", @dossier.relative(file))
        @dossier.files[file] = node
        organizations = @dossier.list(node, "organisations").compact_map { |item| @dossier.text(item, "ref") }.to_set
        contacts = @dossier.list(node, "contacts").compact_map { |item| @dossier.text(item, "ref") }.to_set
        opportunities = @dossier.list(node, "opportunites").compact_map { |item| @dossier.text(item, "ref") }.to_set
        where = @dossier.relative(file)
        (@dossier.list(node, "organisations") + @dossier.list(node, "opportunites") + @dossier.list(node, "activites")).each do |item|
          @dossier.text(item, "responsable").try { |email| error(where, "responsable #{email} n'est pas un utilisateur") unless @emails.includes?(email) }
        end
        (@dossier.list(node, "contacts") + @dossier.list(node, "opportunites") + @dossier.list(node, "activites")).each do |item|
          @dossier.text(item, "organisation").try { |ref| error(where, "organisation « #{ref} » inconnue") unless organizations.includes?(ref) }
        end
        @dossier.list(node, "opportunites").each do |item|
          @dossier.text(item, "contact").try { |ref| error(where, "contact « #{ref} » inconnu") unless contacts.includes?(ref) }
          if @dossier.text(item, "etape") == "lost" && item["perte"]?.nil?
            error(where, "opportunité perdue « #{@dossier.text(item, "titre")} » sans motif (perte)")
          end
        end
        @dossier.list(node, "activites").each do |item|
          @dossier.text(item, "opportunite").try { |ref| error(where, "opportunité « #{ref} » inconnue") unless opportunities.includes?(ref) }
        end
      end

      private def safe?(file : String) : Bool
        !file.starts_with?('/') && !file.split('/').includes?("..")
      end

      private def error(where : String, message : String) : Nil
        @dossier.error(where.starts_with?(@dossier.code) ? where : @dossier.relative(where), message)
      end
    end
  end
end
