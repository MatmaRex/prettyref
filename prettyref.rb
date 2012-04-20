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
			
			self[name.strip] = data
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
	ATTR_RE = /(\w+) *= *("[^">\n]+"|'[^'>\n]+'|[^\s'"]+)/
	# Matches opening ref tag with its attributes as matching group.
	REF_OPEN_RE = /< *ref((?: *#{ATTR_RE})*) *>/
	# Matches closing ref tag.
	REF_CLOSE_RE = /< *\/ *ref *>/
	# Matches self-closing ref tag (shorttag).
	REF_SHORTTAG = /< *ref((?: *#{ATTR_RE})*) *\/ *>/
	
	attr_accessor :orig, :name, :orig_name, :group, :content
	def initialize str, shorttag=false
		@orig = str.dup
			
		if !shorttag
			str.sub!(REF_OPEN_RE){ parse_attrs $1; '' }
			str.sub!(REF_CLOSE_RE, '')
			
			@content = str.strip
			
			if !@name || @name=='test' || @name =~ /^auto(nazwa)?\d+$/
				@name = extract_name @content.dup
			end
		else
			str.sub!(REF_SHORTTAG){ parse_attrs $1; '' }
			@content = nil
			if !@name
				raise 'shorttag and no name'
			else
				if @name=='test' || @name =~ /^autonazwa\d+$/
					@name = false # this means that the name will be determined later by scanning all other ref tags
				end
			end
		end
	end
	
	def parse_attrs str
		str.scan(ATTR_RE).each{|k, v|
			case k
			when 'name'
				name = v.strip
				# strip quotes
				if name[0] == name[-1] and (name[0]=="'" || name[0]=='"')
					name = name[1..-2].strip
				end
				@name = name
				@orig_name = name.dup
			when 'group'
				raise 'ref groups unsupported'
			end
		}
	end
	
	def extract_name str
		# Na kilka sposobów możemy wymyślić nazwę dla refa. Nie powinna ona przekraczać 30 znaków. 
		# W kolejności używamy do tego:
		# 1. PMID/DOI
		# 2. Adresu URL
		# 3. Nazwiska i imienia autora
		# 4. Tytułu dzieła
		# 5. Początkowych słów występujących w refie
		
		if str.start_with? '{{'
			# jeśli mamy szablon, to super
			tpl = Template.new str
			
			case tpl.name
			when 'Cytuj grę komputerową', 'Cytuj książkę', 'Cytuj odcinek', 'Cytuj pismo', 'Cytuj stronę'
				if a = tpl[:pmid]
					ident = "pmid#{a}"
				elsif a = tpl[:doi]
					ident = "doi#{a}"
				elsif a = tpl[:url]
					ident = extract_name_from_uri a
				elsif a = tpl[:autor]
					ident = extract_name_from_words clear_wikitext a
				elsif tpl[:nazwisko] && tpl[:imię]
					ident = extract_name_from_words clear_wikitext "#{tpl[:nazwisko]}  #{tpl[:imię]}"
					# TODO: jest więcej parametrów z nazwiskami...
					# TODO: warto dodać rok?
				elsif a = tpl[:tytuł]
					ident = extract_name_from_words clear_wikitext a
				else
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
		
		words = path.scan(/[\w\d_-]{4,}/).reject{|a| %w[cgi-bin html].include?(a) || a=~/_id$/}
		words = words.map{|w| w.gsub('_','-').gsub(/-+/,'-').gsub(/^-|-$/, '') }
		
		ident = ([host.gsub('.', '-')] + words).join('-')
		
		while ident.length > 30 && !words.empty?
			words.shift
			ident = ([host] + words).join('-')
		end
		
		return ident
	end
	
	def extract_name_from_words str
		words = (UnicodeUtils.nfc str).scan(/(?:\p{L}|\p{M}|\p{N})+/)
		ident = words.inject(''){|id, w| id.length<30 ? (id<<' '<<w) : id }
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

	# build list of refs
	refs = text.scan(/(#{Ref::REF_OPEN_RE}(.+?)#{Ref::REF_CLOSE_RE})/).map{|ary| Ref.new ary.first}

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
	
	# add the shorttags
	shorttags = text.scan(/(#{Ref::REF_SHORTTAG})/).map{|ary| Ref.new ary.first, true}
	shorttags.each{|r| r.name = refs.find{|r2| r2.orig_name == r.orig_name}.name } # find the new names
	refs += shorttags



	# replace refs in text with {{r}} calls
	refs.each do |r|
		text.sub!(r.orig, "{{r|#{r.name}}}")
	end
	nil while text.gsub!(/\{\{r\|([^}]+)\}\}\s*\{\{r\|([^}]+)\}\}/, '{{r|\1|\2}}') # clean up multiple consec. {{r}}


	# place refs in the section
	przypisy_re = /(=+ *Przypisy *=+\s+)?\{\{Przypisy[^}]*\}\}/i

	if text =~ przypisy_re
		data = (
			['== Przypisy ==', '{{Przypisy-lista|'] +
			refs.select{|r| r.content} + # skip shorttags
			['}}']
		).join("\n")
		
		text = text.sub(przypisy_re, data)
	else
		raise 'no refs section present?'
	end

	return text
end



require 'sunflower'
s = Sunflower.new.login

p = Page.new ARGV[0]
p.text = magical_ref_cleaning p.text
p.dump
