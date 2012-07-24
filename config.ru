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
			@headers ||= {}
			@headers.merge! 'Access-Control-Allow-Origin' => '*'
			
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
							<form method=post action=/ onsubmit="if(this.text.value=='') this.method='get'; else this.method='post' ">
								Title: <input name=title> <br>
								Or – text: <textarea name=text rows=1 style="overflow-y:scroll"></textarea> <br>
								<br>
								Format: <select name=format><option>plain<option>json<option>jsonp</select> <input type=submit>
							</form>
							
							<p><a href=https://github.com/MatmaRex/prettyref>GitHub</a>.
						</body>
					</html>
				EOF
				
				@status = 400
				@headers.merge! "Content-Type" => "text/html"
				return form
			else
				text = Page.new(title).text if !text
				output = magical_ref_cleaning text
				output_struct = {status: 200, content: output }
				
				@status = 200
				
				case format
				when 'json'
					@headers.merge! "Content-Type" => "application/json"
					return output_struct.to_json
				when 'jsonp'
					@headers.merge! "Content-Type" => "text/javascript"
					return "#{callback}(#{output_struct.to_json})"
				else
					@headers.merge! "Content-Type" => "text/plain"
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
				@headers.merge! "Content-Type" => "application/json"
				return output_struct.to_json
			when 'jsonp'
				@status = 200
				@headers.merge! "Content-Type" => "text/javascript"
				return "#{callback}(#{output_struct.to_json})"
			else
				@status = 500
				@headers.merge! "Content-Type" => "text/plain"
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
