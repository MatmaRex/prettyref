# coding: utf-8

begin

require 'camping'
require 'sunflower'
require 'json'
require './prettyref'


$s ||= Sunflower.new('pl.wikipedia.org')

Camping.goes :Web
module Web::Controllers
	class Index
		def get
			title = (@request["title"] && @request["title"].strip != '') ? @request["title"].strip : nil
			text = (@request["text"] && @request["text"].strip != '') ? @request["text"] : nil
			format = (@request["format"] && @request["format"].strip != '') ? @request["format"].strip : 'plain'
			callback = (@request["callback"] && @request["callback"].strip != '') ? @request["callback"].strip : 'void'
			
			
			if !title and !text
				form = <<-EOF.gsub(/^\t{5}/, '')
					<!doctype html>
					<html>
						<head>
							<meta charset=utf-8>
							<title>Prettyref</title>
						</head>
						<body>
							<form method=get action=/>
								Title: <input name=title> <br>
								Format: <select name=format><option>plain<option>json<option>jsonp</select> <br>
								<input type=submit>
							</form>
							
							<p><a href=https://github.com/MatmaRex/prettyref>GitHub</a>.
						</body>
					</html>
				EOF
				
				@status, @headers = 400, {"Content-Type" => "text/html"}
				return form
			else
				text = Page.new(title).text if !text
				output = magical_ref_cleaning text
				output_struct = {status: 200, content: output }
				
				@status = 200
				
				case format
				when 'json'
					@headers = {"Content-Type" => "application/json"}
					return output_struct.to_json
				when 'jsonp'
					@headers = {"Content-Type" => "text/javascript"}
					return "#{callback}(#{output_struct.to_json})"
				else
					@headers = {"Content-Type" => "text/plain"}
					return output
				end
			end
			
		rescue Exception => e
			$stderr.puts e
			$stderr.puts e.backtrace

			output = ([e.to_s]+e.backtrace).join("\n")
			output_struct = {status: 500, error: e.to_s, backtrace: output }

			case format
			when 'json'
				@status = 200
				@headers = {"Content-Type" => "application/json"}
				return output_struct.to_json
			when 'jsonp'
				@status = 200
				@headers = {"Content-Type" => "text/javascript"}
				return "#{callback}(#{output_struct.to_json})"
			else
				@status = 500
				@headers = {"Content-Type" => "text/plain"}
				return output
			end
		end
		alias post get
	end
end


use Rack::ShowExceptions
run Web


rescue Exception
	$stderr.p $!
	$stderr.puts $!.backtrace
end
