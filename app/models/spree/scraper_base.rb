require 'nokogiri'
module Spree
  class ScraperBase
    attr_reader :login_info, :addresses, :selectors

    def initialize
      shipping_config = YAML.load_file("spree-extensions/spree_extra_shipment_status/config/shipping_update.yml")
      @config = shipping_config["#{ENV['RAILS_ENV'] || "development"}"]
    end

    def get_single_text html_doc, selector
      html_doc.at_css(selector)
    end

    def get_multiple_text html_doc, selector
      html_doc.css(selector)
    end

    private
    def get_config args
      tmp = @config
      args.split('.').each do |arg|
        tmp = tmp[arg]
      end
      tmp
    end
  end
end
