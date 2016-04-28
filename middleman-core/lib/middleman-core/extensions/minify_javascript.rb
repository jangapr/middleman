require 'middleman-core/contracts'
require 'memoist'

# Minify Javascript Extension
class Middleman::Extensions::MinifyJavascript < ::Middleman::Extension
  option :inline, false, 'Whether to minify JS inline within HTML files'
  option :ignore, [], 'Patterns to avoid minifying'
  option :compressor, proc {
    require 'uglifier'
    ::Uglifier.new
  }, 'Set the JS compressor to use.'
  option :content_types, %w(application/javascript), 'Content types of resources that contain JS', set: true
  option :inline_content_types, %w(text/html text/php), 'Content types of resources that contain inline JS', set: true

  INLINE_JS_REGEX = /(<script[^>]*>\s*(?:\/\/(?:(?:<!--)|(?:<!\[CDATA\[))\n)?)(.*?)((?:(?:\n\s*)?\/\/(?:(?:-->)|(?:\]\]>)))?\s*<\/script>)/m

  def initialize(app, options_hash={}, &block)
    super

    @ignore = Array(options[:ignore]) + [/\.min\./]
    @compressor = options[:compressor]
    @compressor = @compressor.to_proc if @compressor.respond_to? :to_proc
    @compressor = @compressor.call if @compressor.is_a? Proc
  end

  Contract ResourceList => ResourceList
  def manipulate_resource_list(resources)
    resources.each do |r|
      type = r.content_type.try(:slice, /^[^;]*/)
      if options[:inline] && minifiable_inline?(type)
        r.filters << method(:minify_inline)
      elsif minifiable?(type) && !ignore?(r.destination_path)
        r.filters << method(:minify)
      end
    end
  end

  # Whether the path should be ignored
  Contract String => Bool
  def ignore?(path)
    @ignore.any? { |ignore| ::Middleman::Util.path_match(ignore, path) }
  end
  memoize :ignore?

  # Whether this type of content can be minified
  Contract Maybe[String] => Bool
  def minifiable?(content_type)
    options[:content_types].include?(content_type)
  end
  memoize :minifiable?

  # Whether this type of content contains inline content that can be minified
  Contract Maybe[String] => Bool
  def minifiable_inline?(content_type)
    options[:inline_content_types].include?(content_type)
  end
  memoize :minifiable_inline?

  # Minify the content
  Contract String => String
  def minify(content)
    @compressor.compress(content)
  rescue ::ExecJS::ProgramError => e
    warn "WARNING: Couldn't compress JavaScript in #{@path}: #{e.message}"
    content
  end
  memoize :minify

  # Detect and minify inline content
  Contract String => String
  def minify_inline(content)
    content.gsub(INLINE_JS_REGEX) do |match|
      first = $1
      inline_content = $2
      last = $3

      # Only compress script tags that contain JavaScript (as opposed to
      # something like jQuery templates, identified with a "text/html" type).
      if !first.include?('type=') || first.include?('text/javascript')
        first + minify(inline_content) + last
      else
        match
      end
    end
  end
  memoize :minify_inline
end
