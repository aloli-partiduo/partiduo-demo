# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDemo
  module Validation
    # Cohérence des résultats attendus (`attendus.yml`) avec les opérations
    # déclarées : chaque contrôle est recalculé à partir des données quand
    # c'est possible (écritures, ventes, relevés, registres), sinon signalé
    # comme vérifié au chargement seulement.
    class Expectations
      # Préfixes de comptes mouvementés par une opération sans que le
      # validateur en connaisse les montants (contreparties, règlements,
      # écritures produites par un module).
      UNMODELED = {
        "facture"                => %w[41 5],
        "devis"                  => %w[41 5],
        "achat"                  => %w[40 445 5],
        "banque"                 => %w[5],
        "declaration_tva"        => %w[445 5],
        "justificatif"           => %w[40 445 5],
        "facture_plateforme"     => %w[40 445 5 6],
        "inventaire"             => %w[3 6],
        "mouvement_stock"        => %w[3 6],
        "recapitulatives"        => %w[41 445 5 7],
        "rejet_reglement"        => %w[41 5 6 7],
        "liberal_recette"        => [""],
        "liberal_depense"        => [""],
        "liberal_immobilisation" => [""],
        "liberal_cloture"        => [""],
        "perso_operation"        => %w[5 6 7 1 2],
      }

      record Sale, day : Time, kind : String, lines : Array({String, BigDecimal, BigDecimal})

      def initialize(@dossier : DossierCheck)
      end

      def run : Nil
        @dossier.list(@dossier.expected, "controles").each_with_index do |control, index|
          where = "attendus.yml : controles[#{index}] (#{@dossier.text(control, "type")})"
          check(control, where)
        end
      end

      private def check(control : YAML::Any, where : String) : Nil
        type = @dossier.text(control, "type")
        case type
        when "balance_equilibree"  then confirm(where, "écritures déclarées équilibrées (contrôle des écritures)")
        when "total_debit_minimum" then skip(where, "total des débits : vérifié au chargement seulement")
        when "solde_comptes"       then account_balance(control, where)
        when "declarations_tva"    then compare(where, control, "nombre", count_vat_returns(control))
        when "factures"            then invoices(control, where)
        when "releves"             then compare(where, control, "nombre", count_statements(control))
        when "mouvements_stock"    then stock(control, where)
        when "teledeclarations"    then filings(control, where)
        when "rejets_reglement"    then rejections(control, where)
        when "micro_registres"     then micro(control, where)
        when "urssaf_declarations" then compare(where, control, "nombre", count_type("urssaf_declaration", "periode", control))
        when "liberal_journal"     then liberal(control, where)
        when "exercice_liberal"    then liberal_year(control, where)
        when "previsions"          then compare(where, control, "nombre", (executed("prevision").size + executed("perso_budget").size).to_s)
        when "perso_comptes"       then compare(where, control, "nombre", perso_accounts.to_s)
        when "perso_budget"        then compare(where, control, "nombre", perso_budget_lines(control))
        when "perso_valorisations" then compare(where, control, "nombre", executed("perso_valorisation").size.to_s)
        when "perso_emprunt"       then skip(where, "capital restant dû du tableau d'amortissement : vérifié au chargement seulement")
        when "perso_echeances"     then skip(where, "échéances rapprochées des relevés : vérifié au chargement seulement")
        else                            @dossier.error(@dossier.relative(where), "type de contrôle inconnu « #{type} »")
        end
      end

      # Comptes du foyer : ceux de `parametres.yml`, et le compte courant
      # repris d'office au provisionnement.
      private def perso_accounts : Int32
        @dossier.list(@dossier.parameters["perso"]?, "comptes").size + 1
      end

      # Lignes du budget de l'année du contrôle.
      private def perso_budget_lines(control : YAML::Any) : String
        year = year(control) || return "?"
        budgets = executed("perso_budget").select { |(_, operation)| @dossier.text(operation, "annee").try { |text| @dossier.dates.year(text) } == year }
        budgets.sum { |(_, operation)| @dossier.list(operation, "lignes").size }.to_s
      end

      private def year(control : YAML::Any) : Int32?
        text = @dossier.text(control, "exercice") || return
        Dates.year?(text) ? @dossier.dates.year(text) : nil
      end

      # Opérations d'un type jouées au chargement : datées (au plus tard le
      # jour du chargement), puis celles de fin, au jour du chargement.
      private def executed(type : String) : Array({Time, YAML::Any})
        list = @dossier.dated_operations.select { |(_, operation)| @dossier.text(operation, "type") == type }
        @dossier.list(@dossier.files["operations.yml"], "fin").each do |operation|
          list << {@dossier.dates.today, operation} if @dossier.text(operation, "type") == type
        end
        list
      end

      # Montants comparés au centime, autres valeurs telles quelles.
      AMOUNT_KEYS = %w[montant recettes achats depenses frais]

      private def compare(where : String, control : YAML::Any, key : String, actual : String) : Nil
        raw = control[key]?.try(&.raw)
        expected = AMOUNT_KEYS.includes?(key) && raw.is_a?(String) ? decimal(@dossier.amount(raw)) : raw.to_s
        if expected == actual
          confirm(where, "#{key} recalculé : #{actual}")
        else
          @dossier.error(@dossier.relative(where), "#{key} attendu #{expected}, recalculé #{actual} à partir des opérations")
        end
      end

      private def confirm(where : String, message : String) : Nil
        @dossier.note("#{@dossier.relative(where)} : #{message}")
      end

      private def skip(where : String, message : String) : Nil
        @dossier.note("#{@dossier.relative(where)} : #{message}")
      end

      private def decimal(value : BigDecimal) : String
        cents = (value * 100).round.to_big_i
        sign = cents < 0 ? "-" : ""
        cents = cents.abs
        "#{sign}#{cents // 100}.#{(cents % 100).to_s.rjust(2, '0')}"
      end

      # --- Soldes de comptes ------------------------------------------------------------

      private def account_balance(control : YAML::Any, where : String) : Nil
        year = year(control) || return
        prefix = @dossier.text(control, "prefixe") || return
        sales_only = @dossier.text(control, "journaux") == "ventes"
        if @dossier.text(control, "journaux") == "achats"
          return skip(where, "journaux d'achats : vérifié au chargement seulement")
        end
        tainted = taints(year, sales_only)
        if blocker = tainted.find { |taint| prefix.starts_with?(taint) || taint.starts_with?(prefix) }
          return skip(where, "comptes #{prefix} mouvementés par des opérations non recalculées (#{blocker.empty? ? "module" : blocker}*) : vérifié au chargement seulement")
        end
        postings = sales_postings
        postings += entry_postings + @dossier.statement_postings unless sales_only
        total = postings.select { |posting| posting.day.year == year && posting.account.starts_with?(prefix) }
          .sum(BigDecimal.new(0), &.amount)
        total = -total if @dossier.text(control, "sens") == "credit"
        compare(where, control, "montant", decimal(total))
      end

      private def taints(year : Int32, sales_only : Bool) : Array(String)
        list = [] of String
        @dossier.dated_operations.each do |(day, operation)|
          next unless day.year == year
          type = @dossier.text(operation, "type") || next
          next if sales_only && !type.in?("recapitulatives", "rejet_reglement")
          list.concat(UNMODELED[type]? || [] of String)
        end
        @dossier.list(@dossier.files["operations.yml"], "fin").each do |operation|
          next unless @dossier.dates.today.year == year
          type = @dossier.text(operation, "type") || next
          next if sales_only && !type.in?("recapitulatives", "rejet_reglement")
          list.concat(UNMODELED[type]? || [] of String)
        end
        list.uniq
      end

      # Écritures saisies (`ecriture`) et contreparties des extraits
      # bancaires (`banque`) et des achats.
      private def entry_postings : Array(Posting)
        list = [] of Posting
        @dossier.dated_operations.each do |(day, operation)|
          case @dossier.text(operation, "type")
          when "ecriture"
            @dossier.list(operation, "lignes").each do |line|
              account = @dossier.text(line, "compte") || next
              amount = @dossier.amount(@dossier.text(line, "debit")) - @dossier.amount(@dossier.text(line, "credit"))
              list << Posting.new(day, account, amount)
            end
          when "banque"
            @dossier.list(operation, "lignes").each do |line|
              account = @dossier.text(line, "compte") || next
              list << Posting.new(day, account, -@dossier.amount(@dossier.text(line, "montant")))
            end
          when "achat"
            @dossier.list(operation, "lignes").each do |line|
              if code = @dossier.text(line, "article")
                item = @dossier.items[code]? || next
                account = @dossier.text(item, "compte") || next
                list << Posting.new(day, account, @dossier.quantity(line["quantite"]?) * @dossier.amount(@dossier.text(line, "prix")))
              elsif account = @dossier.text(line, "compte")
                list << Posting.new(day, account, @dossier.amount(@dossier.text(line, "montant")))
              end
            end
          end
        end
        list
      end

      # --- Ventes ---------------------------------------------------------------------------

      # Documents de vente émis : factures, avoirs, factures d'acompte et
      # factures finales des devis acceptés, à leur date.
      private def sales : Array(Sale)
        @sales ||= begin
          list = [] of Sale
          today = @dossier.dates.today
          @dossier.dated_operations.each do |(day, operation)|
            case @dossier.text(operation, "type")
            when "facture"
              list << Sale.new(day, "invoice", lines(@dossier.list(operation, "lignes"), 1))
              if credit = operation["avoir"]?
                on = day + (credit["delai"]?.try(&.as_i?) || 0).days
                list << Sale.new(on, "credit_note", lines(@dossier.list(credit, "lignes"), -1)) if on <= today
              end
            when "devis"
              accepted = operation["acceptation"]? || next
              total = lines(@dossier.list(operation, "lignes"), 1)
              on = day + (accepted["delai"]?.try(&.as_i?) || 0).days
              next if on > today
              percent = @dossier.amount(@dossier.text(accepted, "acompte"))
              deposit = total.map { |(account, net, vat)| {account, (net * percent / 100).round(2), (vat * percent / 100).round(2)} }
              list << Sale.new(on, "deposit_invoice", deposit) if percent > 0
              final = accepted["facture_finale"]? || next
              last = on + (final["delai"]?.try(&.as_i?) || 0).days
              next if last > today
              rest = total.map_with_index { |(account, net, vat), index| {account, net - deposit[index][1], vat - deposit[index][2]} }
              list << Sale.new(last, "invoice", percent > 0 ? rest : total)
            end
          end
          list
        end
      end

      @sales : Array(Sale)? = nil

      # Lignes d'un document : compte de produit, montant HT, TVA (signés).
      private def lines(list : Array(YAML::Any), sign : Int32) : Array({String, BigDecimal, BigDecimal})
        rates = @dossier.rates
        list.compact_map do |line|
          item = @dossier.items[@dossier.text(line, "article") || ""]? || next
          net = @dossier.quantity(line["quantite"]?) * @dossier.amount(@dossier.text(item, "prix_vente")) * sign
          rate = rates[@dossier.text(item, "taux") || ""]? || BigDecimal.new(0)
          {@dossier.text(item, "compte") || "70", net, (net * rate / 100).round(2)}
        end
      end

      # Produits au crédit (montants négatifs), TVA collectée au crédit.
      private def sales_postings : Array(Posting)
        sales.flat_map do |sale|
          sale.lines.flat_map do |(account, net, vat)|
            [Posting.new(sale.day, account, -net), Posting.new(sale.day, "44571", -vat)]
          end
        end
      end

      private def invoices(control : YAML::Any, where : String) : Nil
        year = year(control) || return
        if !executed("recapitulatives").none? { |(day, _)| day.year == year }
          return skip(where, "factures récapitulatives : vérifié au chargement seulement")
        end
        count = sales.count { |sale| sale.kind == "invoice" && sale.day.year == year }
        compare(where, control, "nombre", count.to_s)
      end

      # --- Comptages ------------------------------------------------------------------------

      private def count_vat_returns(control : YAML::Any) : String
        year = year(control) || return "?"
        executed("declaration_tva").count do |(_, operation)|
          text = @dossier.text(operation, "periode")
          text && Dates.period?(text) && @dossier.dates.period(text).year == year
        end.to_s
      end

      private def count_statements(control : YAML::Any) : String
        year = year(control) || return "?"
        reconciled = executed("rapprochement").count do |(_, operation)|
          text = @dossier.text(operation, "mois")
          text && Dates.period?(text) && @dossier.dates.period(text).year == year
        end
        imported = executed("import_releve").count do |(_, operation)|
          reference = @dossier.text(operation["pointage"]?, "reference") || next false
          @dossier.dates.expand_years(reference).ends_with?("/#{year}")
        end
        (reconciled + imported).to_s
      end

      private def count_type(type : String, key : String, control : YAML::Any) : String
        year = year(control) || return "?"
        executed(type).count do |(_, operation)|
          text = @dossier.text(operation, key)
          text && Dates.period?(text) && @dossier.dates.period(text).year == year
        end.to_s
      end

      private def stock(control : YAML::Any, where : String) : Nil
        count = executed("inventaire").size + executed("mouvement_stock").size
        minimum = control["minimum"]?.try(&.as_i?) || 1
        if count >= minimum
          confirm(where, "#{count} opérations de stock ≥ #{minimum}")
        else
          @dossier.error(@dossier.relative(where), "#{count} opérations de stock déclarées, minimum attendu #{minimum}")
        end
      end

      private def filings(control : YAML::Any, where : String) : Nil
        natures = executed("teledeclarations").flat_map do |(_, operation)|
          @dossier.list(operation, "declarations").compact_map { |item| @dossier.text(item, "nature") }
        end
        expected = @dossier.list(control, "natures").compact_map(&.as_s?).sort!
        if natures.sort == expected
          confirm(where, "natures recalculées : #{expected.join(", ")}")
        else
          @dossier.error(@dossier.relative(where), "natures attendues #{expected.join(", ")}, déclarées #{natures.sort.join(", ")}")
        end
      end

      private def rejections(control : YAML::Any, where : String) : Nil
        list = executed("rejet_reglement")
        compare(where, control, "nombre", list.size.to_s)
        fees = @dossier.text(control, "frais") || return
        list.each do |(_, operation)|
          actual = @dossier.amount(@dossier.text(operation, "frais"))
          unless actual == @dossier.amount(fees)
            @dossier.error(@dossier.relative(where), "frais attendus #{fees}, déclarés #{decimal(actual)}")
          end
        end
      end

      # --- Micro-entrepreneur, profession libérale -----------------------------------------

      private def micro(control : YAML::Any, where : String) : Nil
        year = year(control) || return
        receipts = executed("micro_recette").select { |(day, _)| day.year == year }
          .sum(BigDecimal.new(0)) { |(_, operation)| @dossier.amount(@dossier.text(operation, "montant")) }
        @dossier.dated_operations.each do |(day, operation)|
          next unless @dossier.text(operation, "type") == "facture"
          payment = operation["reglement"]? || next
          next unless @dossier.text(payment, "mode") == "encaissement"
          paid = day + (payment["delai"]?.try(&.as_i?) || 0).days
          next unless paid.year == year && paid <= @dossier.dates.today
          receipts += lines(@dossier.list(operation, "lignes"), 1).sum(BigDecimal.new(0)) { |(_, net, vat)| net + vat }
        end
        purchases = executed("micro_achat").select { |(day, _)| day.year == year }
          .sum(BigDecimal.new(0)) { |(_, operation)| @dossier.amount(@dossier.text(operation, "montant")) }
        compare(where, control, "recettes", decimal(receipts))
        compare(where, control, "achats", decimal(purchases))
      end

      private def liberal(control : YAML::Any, where : String) : Nil
        year = year(control) || return
        sum = ->(type : String) do
          executed(type).select { |(day, _)| day.year == year }
            .sum(BigDecimal.new(0)) { |(_, operation)| @dossier.amount(@dossier.text(operation, "montant")) }
        end
        compare(where, control, "recettes", decimal(sum.call("liberal_recette")))
        compare(where, control, "depenses", decimal(sum.call("liberal_depense")))
      end

      private def liberal_year(control : YAML::Any, where : String) : Nil
        year = year(control) || return
        closed = executed("liberal_cloture").any? { |(_, operation)| @dossier.text(operation, "exercice").try { |text| @dossier.dates.year(text) } == year }
        filed = executed("teledeclarations").any? do |(_, operation)|
          @dossier.list(operation, "declarations").any? do |item|
            @dossier.text(item, "nature") == "liasse" && @dossier.text(item, "exercice").try { |text| @dossier.dates.year(text) } == year
          end
        end
        state = closed ? (filed ? "locked" : "closed") : "open"
        compare(where, control, "etat", state)
      end
    end
  end
end
