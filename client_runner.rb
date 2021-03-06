require_relative 'command_input_parse_validator'
require_relative 'quandl_api_client'
require_relative 'data_validator'
require_relative 'data_formatter'
require_relative 'max_drawdown_calculator'
require_relative 'roi_calculator'
require_relative 'notifier'
require_relative 'config/mail_config'

require 'action_mailer'

class ClientRunner
  include CommandInputParseAndValidator
  include RoiCalculator
  include DataValidator

  def run_request(api_client, request_type, command_line_input, email_recipient)
    parse_input_and_validate(command_line_input)
    unless @ticker.nil? || @date.nil?
      response = send_request_to_api(api_client, request_type)
      handle_response(response, email_recipient)
    end
  end

  private

    def handle_response(response, email_recipient)
      if response['quandl_error']
        puts response['quandl_error']
      elsif response[:error]
        puts response[:error]
      elsif valid_data_format?(response)
        roi, max_drawdown = calculate_roi_and_max_drawdown(response)
        send_email_notification(email_recipient, {roi: roi, max_drawdown: max_drawdown})
      else
        puts 'something probably did not go as you wanted'
      end
    end

    def send_email_notification(recipient, message_components = {})
      body = "ROI: #{to_percent(message_components[:roi])} % \n"\
             "Max drawdown: #{to_percent(message_components[:max_drawdown])} %"
      message = Notifier.welcome(recipient, body)
      message.deliver_now
    end

    def parse_input_and_validate(command_line_input) # => 'aapl' '2017-08-01'
      @ticker, @date = parse_and_validate_input(command_line_input)
    end

    def retry_request(api_client, request_type)
      3.times { api_client.send(request_type, @ticker, @date) }
    end

    def send_request_to_api(api_client, request_type)
      begin
        api_client.send(request_type, @ticker, @date)
      rescue
        retry_request(api_client, request_type)
      end
    end

    def valid_data_format?(table_data)
      validate_data(table_data)
    end

    def calculate_roi_and_max_drawdown(json)
      closing_prices = reformat_data(json)
      [roi(closing_prices.first, closing_prices.last), max_drawdown(closing_prices)]
    end

    def reformat_data(json) # =># [{ date: 2017-01-01, close_price: 31 }]
      DataFormatter.new(json).closing_prices
    end

    def max_drawdown(date_and_close_price_data)
      MaxDrawdownCalculator.new(date_and_close_price_data).max_drawdown_percentage
    end

    def roi(initial_price, final_value)
      return_on_investment(initial_price, final_value)
    end

    # Maybe should move this to a separate class cause it doesn't really belong in
    # ClientRunner, but I'll leave it for now.
    def to_percent(float)
      (float * 100).round(1)
    end
end
