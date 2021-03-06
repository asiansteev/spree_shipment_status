require 'open-uri'
require 'mechanize'
module Spree
  class The82Api < Spree::ScraperBase
    attr_reader :xpaths

    def initialize
      super
      @agent = Mechanize.new
      @addresses = get_config 'api.the82.address'
      @selectors = get_config 'api.the82.selector'
      @xpaths = get_config 'api.the82.xpath'
      @korean_name_convert = YAML.load_file("#{Rails.root}/config/korean_name_convert.yml")
    end

    def post_shipment_status shipment
      parameters = {}
      parameters[:userid] = ENV['OHMYZIP_USERID']
      parameters[:authkey] = ENV['OHMYZIP_PASSWORD']
      if shipment.json_kr_tracking_id
        parameters[:transnum] = shipment.json_kr_tracking_id
      elsif shipment.forwarding_id
        parameters[:orderno] = shipment.forwarding_id
      else
        return nil
      end
      page = @agent.post self.addresses['shipment_status'], parameters
      Rails.logger.info "shipping-update" + page.body.force_encoding('UTF-8')
      Nokogiri::XML(page.body)
    end

    def post_shipment_registration shipment
      header = {}
      header['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
      header['Accept-Encoding'] = 'gzip, deflate'
      header['Accept-Language'] = 'ko-KR,ko;q=0.8,en-US;q=0.6,en;q=0.4'
      parameters = self.assign_data_for_registration shipment
      Rails.logger.info "shipping-update" + parameters.to_s
      page = @agent.post self.addresses['shipment_registration'], parameters, header
      Rails.logger.info "shipping-update" + page.body.force_encoding('UTF-8')
      rtn = {}
      page.body.split("|").each do |str|
        tmp = str.split("=")
        rtn[tmp[0]] = tmp[1]
      end
      rtn
    end
    def assign_data_for_registration shipment
      address = shipment.address
      order = shipment.order
      rtn = {}
      rtn.compare_by_identity
      rtn["gubun"] = 'D'
      rtn["jisa"] = 'IL'
      rtn["custid"] = ENV['OHMYZIP_USERID']
      rtn["authkey"] = ENV['OHMYZIP_PASSWORD']
      rtn["receiverkrnm"] = replace_comma(address.firstname)
      rtn["receiverennm"] = convert_korean_name(replace_comma(address.firstname))
      rtn["telno"] = "N/A"
      rtn["mobile"] = replace_comma(address.phone).delete(' ')
      if address.customs_no.present?
        if address.customs_no[0] == "P"
          rtn["pgno"] = address.customs_no
        else
          rtn["registno"] = address.customs_no
        end
      end
      rtn["memid"] = "N/A"
      rtn["tax"] = "com"
      rtn["zipcode"] = replace_comma(address.zipcode).delete(' ')
      rtn["address1"] = replace_comma(address.address1)
      rtn["address2"] = replace_comma(address.address2)
      if address.other_comment.present?
        rtn["deliverymemo"] = replace_comma(address.other_comment)
      else
        rtn["deliverymemo"] = "N/A"
      end
      rtn["privateno"] = "N/A"
      rtn["listpass"] = "1"
      rtn["detailtype"] = "0"
      rtn["package"] = "1"
      rtn["package2"] = "1"
      rtn["isinvoice"] = "1"
      rtn["protectpackage"] = "0"
      #rtn["isdebug"] = "1"
      order_no = "#{order.number}-#{Time.now.to_i}" 
      order.line_items.each do |li|
        var = li.variant
        prod = li.product
        next if var.nil? or prod.nil?
        if shipment.json_store_order_id[prod.merchant].present? and shipment.json_store_order_id[prod.merchant] == 'FAILED'
          Rails.logger.info "shipping-update failed product skip!#{shipment.json_store_order_id}"
          next
        end
        rtn["ominc"] = order_no
        rtn["brand"] = replace_comma(prod.brand)
        rtn["prodnm"] = replace_comma(prod.name)
        rtn["produrl"] = "https://gosnapshop.com/products/#{prod.slug}"
        rtn["prodimage"] = prod.try(:images).try(:first).try(:attachment).url("large")
        properties = prod.product_properties.select {|pp| pp.property.name == 'Color'}
        unless properties.empty?
          rtn["prodcolor"] = replace_comma(properties.first.value)
        else
          rtn["prodcolor"] = "N/A"
        end
        size = var.option_values.find { |o| o.option_type.name.include? "size" }
        unless size.nil?
          rtn["prodsize"] = replace_comma(size.name)
        else
          rtn["prodsize"] = "N/A"
        end
        rtn["qty"] = li.quantity.to_s
        rtn["cost"] = li.price.to_f.to_s
        unless shipment.json_store_order_id[prod.merchant].nil? or shipment.json_store_order_id[prod.merchant].empty?
          orderno = shipment.json_store_order_id[prod.merchant].join(" ")
          trackno = shipment.json_us_tracking_id[prod.merchant].map{|k,v|v}.join(" ")
          if orderno.length < 50 and trackno.length < 50
            rtn["orderno"] = orderno
            rtn["trackno"] = trackno
          else
            Rails.logger.info "shipping-update check orderno and trackno"
            rtn["orderno"] = "manual input"
            rtn["trackno"] = "manual input"
          end
        else
          rtn["orderno"] = "N/A"
          rtn["trackno"] = "N/A"
        end
        rtn["spnm"] = "SNAPSHOP"
        rtn["deliveryType"] = "3"
        rtn["custordno"] = order_no
        rtn["category"] = convert_the82_taxon prod.get_valid_taxon
        if address.other_comment.present?
          rtn["requestmemo"] = replace_comma(address.other_comment)
        else
          rtn["requestmemo"] = "N/A"
        end
      end
      rtn
    end

    private

    def replace_comma string
      if string.nil? or string.empty?
        "N/A"
      else
        string.gsub(",", " ").gsub("'", " ").gsub("`", " ").gsub("\"","")
      end
    end
    def convert_the82_taxon taxon
      return "ACCESSORIES" if taxon.nil?
      case taxon.id
      when 72, 82, 159, 160
        return "ACCESSORIES"
      when 52, 51, 64, 49, 50, 154, 48, 53, 152
        return "BABIES GARMENTS"
      when 79, 71, 80, 149, 146, 148, 76, 147
        return "BAGS"
      when 162, 163
        return "BELT OF LEATHER"
        #return "GLOVE OF LEATHER"
      when 158, 150
        return "HAT"
      when 40, 47
        return "KNITTED T-SHIRTS"
      when 38
        return "MENS COAT"
      when 39
        return "MENS JACKETS"
      when 36, 37, 60
        return "MENS PANTS"
        #return "MENS SUITS"
      when 34, 35
        return "MENS T-SHIRTS"
        #return "FABRIC GLOVES"
        #return "OTHER GARMENT"
        #return "SCARF"
      when 22,24,25,155,14,59,10,13,11,12,9,26,28,29,169,65,153,16,20,17,15,19,18
        return "SHOES"
      when 45, 55
        return "SKIRTS"
      when 77
        return "SOCKS"
      when 73
        return "SUNGLASSES"
      when 81
        return "TIE"
        #return "VEST"
      when 83, 84, 74, 78
        return "WATCH"
      when 58, 57, 151, 42
        return "WOMANS CLOTHING"
      when 61
        return "WOMANS COAT"
      when 46
        return "WOMANS JACKETS"
      when 43, 44, 56
        return "WOMANS PANTS"
      when 54, 62, 41
        return "WOMANS T-SHIRTS"
      else
        return "ACCESSORIES"
      end
    end
  end
end
