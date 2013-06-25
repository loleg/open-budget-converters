# encoding: UTF-8

module OpenBudget
  class Budget
    attr_accessor :nodes, :meta

    def initialize
      @nodes = []
      @node_index = {}
    end

    def get_node id_path, names
      id = id_path.join '_'
      node = @node_index[id] ||= lambda do
        node = Node.new
        node.id = id

        # add to collection
        if id_path.length > 1
          parent = get_node id_path.take(id_path.length - 1), names.take(names.length - 1)
          node.parent = parent
          parent.children
        else
          node.touch
          @nodes
        end << node

        node
      end.call

      name = names[id_path.length - 1].to_s.strip
      if name.blank?
        puts "blank name id_path #{id_path.to_s} names #{names.to_s}"
      end
      node.name = name
      node
    end

    def as_json(options = nil)
      {
        meta: meta,
        data: nodes
      }
    end

    def load_meta file_path
      @meta = JSON.parse File.read(file_path)
    end

    def from_finstabe_bfh_csv file_path
      CSV.foreach(file_path, :encoding => 'windows-1251:utf-8', :headers => true, :header_converters => :symbol, :converters => :all) do |row|
        if !@meta
          @meta = {
            name: row[:gemeinde],
            bfs_no: row[:bfsnr]
          }
        end

        account_type = row[:kontenbereich_nummer].to_i
        if [3, 4, 5, 6].include? account_type
          node = get_node \
            [row[:aufgabenbereich_nummer], row[:aufgabe_nummer], row[:aufgabenstelle_nummer]].reject(&:blank?),
            [row[:aufgabenbereich_name], row[:aufgabe_name], row[:aufgabenstelle_name]].reject(&:blank?)

          # ToDo: seperate "investitionsrechnung" [5, 6] and "laufende rechnung" [3, 4]
          if [3, 5].include? account_type
            node.add_gross_cost('accounts', row[:jahr], row[:saldo])
          elsif [4, 6].include? account_type
            node.add_revenue('accounts', row[:jahr], row[:saldo])
          end
        end
      end
    end

    def from_zurich_csv file_path, col_sep
      # :encoding => 'windows-1251:utf-8', 
      CSV.foreach(file_path, :col_sep => col_sep, :headers => true, :header_converters => :symbol, :converters => :all) do |row|
        
        # p row
        
        next if row[:bezeichnung].blank?

        row[:bezeichnung].strip!
        code = row[:code].to_s
        konto = row[:konto].to_s.strip.gsub(' ', '_')
        account_type = konto[0].to_i
        # if [3, 4, 5, 6].include? account_type

        dienstabteilung = row[:dienstabteilung]
        if dienstabteilung == 'Kultur' && /^15[0-9]{2}$/.match(code)
          code = '1501'
        elsif dienstabteilung == 'Museum Rietberg' && /^152[0-4]$/.match(code)
          code = '1520'
        end

        id_path = [
          code[0..1], # Departement
          code, # [2..3] = Dienstabteilung
          # konto[0..1], # seperate by account purpose
          konto[0..-1] # account # minus account_type
        ].each(&:strip).reject(&:blank?)
        names = [
          row[:departement],
          dienstabteilung,
          # '-',
          row[:bezeichnung]
        ]

        node = get_node id_path, names

        # ToDo: seperate "investitionsrechnung" [5, 6] and "laufende rechnung" [3, 4]


        method = nil
        case row[:bezeichnung]
        # overview row
        when 'Aufwand'#, 'Ausgaben'
          method = :add_gross_cost
        when 'Ertrag'#, 'Einnahmen'
          method = :add_revenue
        # detail row
        else
          if konto.present?
            case account_type
            when 3#, 5 # Aufwand, Ausgaben
              method = :add_gross_cost
            when 4#, 6 # Ertrag, Einnahmen
              method = :add_revenue
            end
          end
        end

        values = [row[:budget_2012_fr], row[:budget_2013_fr], row[:rechnung_2011_fr]].collect do |value|
          value.to_s.gsub('’','').to_f
        end
        case method
        when :add_revenue
          values.collect! do |value|
            value * -1
          end
        end
        if method
          node.method(method).call('budgets', 2012, values[0])
          node.method(method).call('budgets', 2013, values[1])
          # node.method(method).call('accounts', 2011, values[2])
        end

        # budget_2013_fr bezeichnung_sofern_gemss_art_4_fvo_erforderlich:nil
        
        # if [3, 5].include? account_type
        #   node.add_gross_cost('accounts', row[:jahr], row[:saldo])
        # elsif [4, 6].include? account_type
        #   node.add_revenue('accounts', row[:jahr], row[:saldo])
        # end
        # end
      end
    end
  end
end
