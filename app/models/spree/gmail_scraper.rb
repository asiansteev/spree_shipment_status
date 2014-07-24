require 'net/imap'
require 'mail'
require 'date'

module Spree
  class GmailScraper < Spree::ScraperBase
    def initialize
      super
      @imap = Net::IMAP.new('imap.gmail.com', 993, true)
      @login_info = get_config 'login.gmail'
      @addresses = get_config 'email.gmail.address'
      @selectors = get_config 'email.gmail.selector'
    end

    def login id, password
      begin
        @imap.login id, password
        @imap.select('INBOX')
        true
      rescue Net::IMAP::NoResponseError
        false
      end
    end

    def get_html_doc uid
      mail = Mail.new(@imap.uid_fetch(uid, "RFC822")[0].attr["RFC822"])
      Nokogiri::HTML(mail.html_part.decoded)
    end

    def get_uid_list query
      @imap.uid_search(query)
    end

    def get_imap_date day
      Net::IMAP.format_date(Date.today + day)
    end
  end
end
