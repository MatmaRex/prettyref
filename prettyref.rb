# coding: utf-8
require 'uri'
require 'unicode_utils'

# Represents a Wikipedia template. (Simplified parsing, beware.)
class Template < Hash
	CANONICAL_CAPITALISATION = {
		lowercase: ['Cytuj grę komputerową', 'Cytuj książkę', 'Cytuj odcinek', 'Cytuj pismo', 'Cytuj stronę'],
		uppercase: ['GoldBook'],
	}
	
	attr_accessor :name
	def initialize str
		super()
		parse str
	end
	
	def [] a
		super(a.to_s)
	end
	def []= a, b
		super(a.to_s, b)
	end
	
	def parse text
		text.strip!
		text.sub!(/\A{{\s*([^\|]+)/){ @name = $1.strip; @name[0] = @name[0].upcase; '' }
		text.sub!(/\}\}\Z/, '')
		
		# escape pipes in inner templates and links
		text.gsub!(/<<<(#+)>>>/, '<<<#\1>>>')
		3.times{ text.gsub!(/\{\{[^\}]+\}\}/){ $&.gsub(/\|/, '<<<#>>>') } }
		text.gsub!(/\[\[[^\]]+\]\]/){ $&.gsub(/\|/, '<<<#>>>') }
		
		# extract params
		pairs = text.scan(/\|\s*(.+?)\s*=([\s\S]*?)(?=\||\Z)/)
		pairs.each do |name, data|
			data = data.strip.sub(/\A[ \t]+/, '')
			data = data.gsub(/<<<#>>>/, '|').gsub(/<<<#(#+)>>>/, '<<<\1>>>') # unescape
			
			self[name.strip] = data unless data.empty?
		end
	end
	
	
	def to_s
		data = []
		name = @name.dup
		# by default names are stored uppercased
		name[0] = name[0].downcase if CANONICAL_CAPITALISATION[:lowercase].include? name
		data << "{{#{name}"
		
		data += self.map{|param, value| " | #{param} = #{value}" }
		
		data << " }}"
		data.join("")
	end
end

# Represents a Wikipedia reference tag.
class Ref
	# Matches a HTML-like key=value attribute.
	ATTR_RE = /(\w+) *= *("[^">\n]+"|'[^'>\n]+'|[^\s'"\/]+)/
	# Matches opening ref tag with its attributes as matching group.
	REF_OPEN_RE = /< *ref((?: *#{ATTR_RE})*) *>/
	# Matches closing ref tag.
	REF_CLOSE_RE = /< *\/ *ref *>/
	# Matches self-closing ref tag (shorttag), or a regular tag with no content.
	REF_SHORTTAG = /< *ref((?: *#{ATTR_RE})*) *(?:\/ *>|>#{REF_CLOSE_RE})/
	# Matches {{r}} template.
	REF_RETAG = /\{\{\s*[rR]\s*((?:\|[^\|\}]*)+)\}\}/
	
	# Optimal length for ref name. Does not apply in some cases.
	IDENT_MAX_LEN = 25
	
	attr_accessor :orig, :name, :orig_name, :group, :content
	def initialize str, shorttag=false
		@@group_ref_counter ||= Hash.new{|h,k| h[k] = 0}
		
		@orig = str.dup
			
		if !shorttag
			str.sub!(REF_OPEN_RE){ parse_attrs $1; '' }
			str.sub!(REF_CLOSE_RE, '')
			
			@content = str.strip
			
			if !@name || @name =~ /^(auto|autonazwa|test)\d*$/
				@name = extract_name @content.dup
			end
		else
			@content = nil
			
			if str =~ REF_SHORTTAG
				str.sub!(REF_SHORTTAG){ parse_attrs $1; '' }
			elsif str =~ REF_RETAG
				data = str[REF_RETAG, 1].split(/\s*\|\s*/).map(&:strip).select{|a| a and a!=''}
				if data.any?{|a| a.include? '='}
					raise '{{r}} tags with named attributes unsupported'
				end
				if data.length != 1
					raise 'this shouldnt happen'
				end
				
				@name = data[0]
				@orig_name = @name.dup
			end
			
			if !@name
				raise 'shorttag and no name'
			else
				if @name=='test' || @name =~ /^auto(nazwa)?\d+$/
					@name = false # this means that the name will be determined later by scanning all other ref tags
				end
			end
		end
	end
	
	def parse_attrs str
		str.scan(ATTR_RE).each{|k, v|
			v = v.strip
			# strip quotes
			if v[0] == v[-1] and (v[0]=="'" || v[0]=='"')
				v = v[1..-2].strip
			end
			
			case k
			when 'name'
				@name = v.dup
				@orig_name = v.dup
			when 'group'
				@group = v.dup
				@name = "#{@group}#{@@group_ref_counter[@group]+=1}"
			end
		}
	end
	
	def extract_name str
		# Nazwę dla refa możemy wymyślić na kilka sposobów. Nie powinna ona przekraczać 25 (IDENT_MAX_LEN) znaków. 
		# W kolejności używamy do tego:
		# 
		# a) Jeśli ref zawiera jeden ze standardowych szablonów {{cytuj:
		#    1. PMID/DOI
		#    2. Nazwiska autora + roku
		#    3. Tytułu dzieła
		#    4. Adresu URL
		#    5. Samego nazwiska autora
		#    (+ stron, jeśli podano)
		# b) Jeśli ref zawiera jeden z szablonów szczegółowych:
		#    (nie zaimplementowane...)
		# c) Jeśli ref jest zwykłym tekstem:
		#    1. Adresu URL obecnego w tekście
		# 
		# Jeśli nie uda się utworzyć identyfikatora na żaden z powyższych sposobów, powstaje on z początkowych słów 
		# występujących w tekście refa.
		
		if str.start_with? '{{'
			# jeśli mamy szablon, to super
			tpl = Template.new str
			
			case tpl.name
			when 'Cytuj grę komputerową', 'Cytuj książkę', 'Cytuj odcinek', 'Cytuj pismo', 'Cytuj stronę'
				# extract some terms used later
				year = (
					tpl[:rok] ? tpl[:rok] :
					tpl[:data] ? tpl[:data][/\d{3,4}/] :
					nil
				)
				author = (
					tpl[:'nazwisko r'] ? tpl[:'nazwisko r'] :
					tpl[:'autor r'] ? tpl[:'autor r'] :
					tpl[:nazwisko] ? tpl[:nazwisko] :
					tpl[:autor] ? tpl[:autor] :
					nil
				)
				title = tpl[:tytuł] # nie używamy tytułu części czy tomu
				pages = tpl[:strony]
				
				author = extract_name_from_words clear_wikitext author if author
				title  = extract_name_from_words clear_wikitext title  if title
				pages  = pages.gsub(/[-–—]/, '-').gsub(/[^\d-]/, '')   if pages
			
				if a = tpl[:pmid]
					ident = "pmid#{a}"
				elsif a = tpl[:doi]
					ident = "doi#{a}"
				elsif author and year
					ident = author+year
				elsif title
					ident = title
				elsif a = tpl[:url]
					ident = extract_name_from_uri a
				elsif author
					ident = author
				end
				
				ident += "-s#{pages}" if ident and pages
				
				if !ident
					# nic sie nie dopasowalo? dziwne...
					ident = extract_name_from_words clear_wikitext tpl.values.join(" ")
				end
			else
				raise "unsupported cite template #{tpl.name}"
			end
		else
			# a jeśli nie, to pozostaje nam URL albo cokolwiek z treści
			uris = URI.extract str, %w[http https ftp]
			if uris.length > 0
				ident = extract_name_from_uri uris.first
			else
				ident = extract_name_from_words clear_wikitext str
			end
		end
		
		if !ident || ident.strip==''
			ident = 'autonazwa'
		end
		
		ident.strip
	end
	
	def clear_wikitext str
		str.gsub(/\[\[([^\|\]]+)\|([^\]]+)\]\]/, '\2').gsub(/'{2,}/, '')
	end
	
	def extract_name_from_uri uri
		uri_p = URI.parse uri
		
		tld = %w[biz com info name net org pro aero asia cat coop edu gov int jobs mil mobi museum tel travel xxx co]
		cctld = %w[ac ad ae af ag ai al am ao aq ar as at au aw ax az ba bb bd be bf bg bh bi bj bm bn bo br bs bt bw by bz ca cc cd cf cg ch ci ck cl cm cn co cr cu cv cx cy cz de dj dk dm do dz ec ee eg er es et eu fi fj fk fm fo fr ga gd ge gf gg gh gi gl gm gn gp gq gr gs gt gu gw gy hk hm hn hr ht hu id ie il im in io iq ir is it je jm jo jp ke kg kh ki km kn kp kr kw ky kz la lb lc li lk lr ls lt lu lv ly ma mc md me mg mh mk ml mm mn mo mp mq mr ms mt mu mv mw mx my mz na nc ne nf ng ni nl no np nr nu nz om pa pe pf pg ph pk pl pm pn pr ps pt pw py qa re ro rs ru rw sa sb sc sd se sg sh si sk sl sm sn so sr ss st sv sy sz tc td tf tg th tj tk tl tm tn to tr tt tv tw tz ua ug uk us uy uz va vc ve vg vi vn vu wf ws ye za zm zw]
		
		host = uri_p.host.sub(/^www?\d*\./, '').sub(/\.(#{cctld.join('|')})$/, '').sub(/\.(#{tld.join('|')})$/, '')
		path = (uri_p.path||'') + '?' + (uri_p.query||'')
		path = (CGI.unescape(path) rescue path)
		
		words = path.scan(/[\w\d_-]{4,}/).reject{|a| %w[cgi-bin html shtml].include?(a) || a=~/_id$/}
		words = words.map{|w| w.gsub('_','-').gsub(/-+/,'-').gsub(/^-|-$/, '') }
		
		ident = ([host.gsub('.', '-')] + words).join('-')
		
		while ident.length > IDENT_MAX_LEN && !words.empty?
			words.shift
			ident = ([host] + words).join('-')
		end
		
		return ident
	end
	
	def extract_name_from_words str
		words = (UnicodeUtils.nfc str).scan(/(?:\p{L}|\p{M}|\p{N})+/)
		ident = words.inject(''){|id, w| id.length<IDENT_MAX_LEN ? (id<<' '<<w) : id }
		ident
	end
	
	def to_s
		if @content
			fmt = '<ref name="%s">%s</ref>'
			
			if @content.start_with? '{{'
				cont = Template.new(@content.dup).to_s
			else
				cont = @content
			end
			
			fmt % [@name, cont]
		else
			'<ref name="%s" />' % @name
		end
	end
end

# Does all the hard work.
def magical_ref_cleaning text
	text = text.dup
	text.gsub! '<!-- Tytuł wygenerowany przez bota -->', '' # these notices are 100% unnecessary

	# build list of refs
	refs = text.scan(/(#{Ref::REF_OPEN_RE}([\s\S]+?)#{Ref::REF_CLOSE_RE})/).map{|ary| Ref.new ary.first}

	# check for name conflicts
	all_names = refs.map{|r| r.name}.uniq
	if all_names.length != refs.length
		# konflikt...
		# budujemy hash, gdzie klucze to nazwy refow, a wartosci - liczba wystapien
		all_names_hash = {}
		
		refs.each do |r|
			if all_names_hash[r.name]
				# konflikt
				all_names_hash[r.name] += 1
				r.name += all_names_hash[r.name].to_s # dopisujemy kolejna cyfre
				
				if all_names_hash[r.name]
					raise 'solving name conflicts to be implemented...'
				end
			else
				all_names_hash[r.name] = 1
			end
		end
		
	end
	
	# check for dupes
	refs.each_with_index do |ri, i|
		refs.each_with_index do |rj, j|
			next if i == j
			# compare only contents
			if ri.to_s.sub('"'+ri.name+'"', '') == rj.to_s.sub('"'+rj.name+'"', '')
				puts 'dupe found!'
				
				# convert the other to shorttag; this anso ensures it's not matched as a dupe again
				rj.content = nil
				rj.name = ri.name
			end
		end
	end
	
	# add the shorttags
	text.gsub!(Ref::REF_RETAG){ $&.gsub('|', '}}{{r|').gsub('{{r}}', '') } # HACK make multi-{{r}} sort-of work
	
	shorttags = text.scan(/(#{Ref::REF_SHORTTAG})/).map{|ary| Ref.new ary.first, true}
	shorttags += text.scan(/(#{Ref::REF_RETAG})/).map{|ary| Ref.new ary.first, true}
	shorttags.each{|r| # find the new names
		other = refs.find{|r2| r2.orig_name == r.orig_name}
		raise 'shorttag with dangling name' if !other
		r.name, r.group = other.name, other.group
	}
	refs += shorttags


	# replace refs in text with {{r}} calls
	# this might also change the inside of references section - will deal with it later
	refs.each do |r|
		text.sub!(r.orig, "{{r|#{r.name}#{r.group ? "|grupa1=#{r.group}" : ''}}}")
	end
	nil while text.gsub!(/\{\{r\|([^|}]+)\}\}\s*\{\{r\|([^|}]+)\}\}/, '{{r|\1|\2}}') # clean up multiple consec. {{r}}


	# place refs in the section
	przypisy_re = /(=+ *(?:Przypisy|Uwagi) *=+\s+)?(<references[^\/]*\/>|\{\{(?:Przypisy|Uwagi)([^{}]*|\{\{[^{}]+\}\})+\}\}|<references[^\/]*>(.+?)<\/references\s*>)/i

	if text =~ przypisy_re
		old_ref_section = $&
		
		# figure out the heading level used for ref sections and probably thoughout the article
		level = '=='
		if mtc = old_ref_section.match(/\A==+/)
			level = mtc.to_s
		elsif mtc = old_ref_section.match(/stopień\s*=\s*(==+)/)
			level = mtc[1]
		end
		
		group_name_to_heading = {
			nil => 'Przypisy',
			'uwaga' => 'Uwagi'
		}
		heading_order = %w[Uwagi Przypisy]
		
		# get only refs with content (ie. not shorttags) and sort them
		references = refs.select{|r| r.content}.sort_by{|r| UnicodeUtils.casefold r.name}
		# then group them by their group info (that is, by headings they belong to), sort headings
		references = references.group_by{|r| r.group}.sort_by{|k,v| heading_order.index group_name_to_heading[k]}
		# churn out the wikicode for each section
		sections = references.map{|group, refs|
			(
				["#{level} #{group_name_to_heading[group]} #{level}"] +
				['{{Przypisy-lista|'+(group ? "grupa=#{group}|" : '')] +
				refs +
				['}}']
			).join("\n")
		}
		
		# insert new refs section(s) into page code
		# remove all encountered sections, replace first one with ours
		once = true
		text = text.gsub(przypisy_re){
			if once
				once = false
				sections.join "\n\n"
			else
				''
			end
		}
	else
		raise 'no refs section present?'
	end

	return text
end

if __FILE__ == $0
	require 'sunflower'
	s = Sunflower.new.login
	s.summary = 'konwersja przypisów'

	list = readlines()


	list.map{|a| a.strip}.each do |t|
		next unless t and t!=''

		p = Page.new t
		p.text = magical_ref_cleaning p.text
		p.save
	end
end
