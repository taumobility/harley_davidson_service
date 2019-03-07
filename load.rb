require 'bundler'
Bundler.setup
require 'savon'
require "yaml"
require 'roo'
require 'csv'
require 'nokogiri'

class Load

  def initialize()
    # Initialize SOAP client using the WSDL
    @config = YAML.load(File.open('config/config.yml').read)
    @client = Savon.client(:wsdl => @config["wsdl"], log: false, ssl_verify_mode: :none)
  end

  # Call Load on the EchoService
  def load_request()
    # Read xslx file to load the data to LeasePak API
    xlsx = Roo::Spreadsheet.open(@config["path_to_file"])

    xlsx.each_with_pagename do |name, sheet|
      errors = []
      infos = []
      sheet.each_row_streaming(pad_cells: true, offset: 1) do |row|
        next if row.eql?(sheet.first_row)

        puts "Processing request for MANF: #{row[0]}, MODEL: #{row[1]}, NAME:#{row[2]}"

        # Post XML data to LeasePak API to save the model data
        response = @client.call(:load_mnf_mdl, message: { xmlDocument: generate_xml(row) })

        res = Nokogiri.XML(response.hash[:envelope][:body][:load_mnf_mdl_response][:return])

        if res.search('ERROR').text.eql?("")
          infos << "#{row[2]} - #{res.search('INFO').text.split(".")[1]}"
        else
          errors << "#{row[2]} - #{res.search('ERROR').text}"
        end
      end

      puts "Generating Processing Summary"
      # Store the responses from LeasePak API in log file
      File.open('log/responses.log', 'a') do |line|
        line.puts "\r" + "Initial Load for Harley Davidson Processed at #{Time.now}"

        line.puts "\r" + "Summary"
        line.puts "#{infos.size} Updated successfully"
        line.puts "#{errors.size} Errors"

        line.puts "\r" + "Updated successfully"
        infos.each do |info|
          line.puts "#{info}"
        end unless infos.empty?

        line.puts "\r" + "Errors"
        errors.each do |error|
          line.puts "#{error}"
        end unless errors.empty?
      end
    end

  rescue Savon::Error => exception
    # Store message in log if client failes to connect with LeasePak API
    File.open('log/connection_error.log', 'a') do |line|
      line.puts "An error occurred while calling the LeasePak: #{exception.message}"
    end
  end

  private

  # generate XML data from the data read from xsls file
  def generate_xml(row)
    xml = Builder::XmlMarkup.new

    xml.LPAuxTableMaint do |table|
      table.RECORD do |d|
        d.manf(row[0])
        d.model(row[1])
        d.name(row[2])
      end
    end
  end
end

if __FILE__ == $0
  # Initialize the EchoService client and call operations
  load = Load.new
  load.load_request()
end
