# frozen_string_literal: true

class Page::Renderer
  require "rouge/plugins/redcarpet"

  def self.render(text, options = {})
    new.render(text, options)
  end

  def render(text, options = {})
    html = markdown(options).render(Emoji.parse(text, sanitize: false))

    # It's like our own little HTML::Pipeline. These methods are easily
    # switchable to HTML::Pipeline steps in the future, if we so wish.
    doc = Nokogiri::HTML.fragment(html)
    doc = add_custom_ids(doc)
    doc = add_custom_classes(doc)
    doc = add_automatic_ids_to_headings(doc)
    doc = add_table_of_contents(doc)
    doc = fix_curl_highlighting(doc)
    doc = add_code_filenames(doc)
    doc.to_html.html_safe
  end

  private

  def markdown(options)
    Redcarpet::Markdown.new(HTMLWithSyntaxHighlighting.new(options), autolink: true,
                                                                     space_after_headers: true,
                                                                     fenced_code_blocks: true)
  end

  class HTMLWithSyntaxHighlighting < Redcarpet::Render::HTML
    include Rouge::Plugins::Redcarpet

    def initialize(options = {})
      @options = options
      super()
    end

    def image(link, title, alt)
      url = Camo::UrlBuilder.build(link) unless link.nil?

      %{<img src="#{EscapeUtils.escape_html(url || '')}" alt="#{EscapeUtils.escape_html(alt || '')}" class="#{@options[:img_classes]}"/>}
    end

    def codespan(code)
      %{<code class="dark-gray border border-gray rounded" style="padding: .1em .25em; font-size: 85%">#{EscapeUtils.escape_html(code)}</code>}
    end
  end

  def add_automatic_ids_to_headings(doc)
    doc.search('./h2').each do |node|
      node['id'] = node.text.to_url if node['id'].blank?

      # Next we find all the h3 siblings between this, and the next h2, and add
      # automatic ids to them if they don't have a manual one set already
      sibling_node = node
      while sibling_node = sibling_node.next_sibling
        break if sibling_node.matches?('h2')

        next unless sibling_node['id'].blank? && sibling_node.matches?('h3')

        sibling_node['id'] = node['id'] + "-" + sibling_node.text.to_url
      end
    end

    doc
  end

  def add_table_of_contents(doc)
    # First, we find all the top-level h2s
    headings = doc.search('./h2')

    # Second, we make them all linkable and give them the right classes.
    headings.each do |node|
      node['class'] = 'Docs__heading'
      node.add_child(<<~HTML)
        <a href="##{node['id']}" aria-hidden="true" class="Docs__heading__anchor"></a>
      HTML
    end

    # Third, we generate and replace the actual toc.
    doc.search('./p').each do |node|
      next unless node.to_html == '<p>{:toc}</p>'

      if headings.empty?
        node.replace('')
      else
        node.replace(<<~HTML.strip)
          <div class="Docs__toc">
            <p>On this page:</p>
            <ul>
              #{headings.map {|heading|
                %{<li><a href="##{heading['id']}">#{heading.text.strip}</a></li>}
              }.join("")}
            </ul>
          </div>
        HTML
      end
    end
    
    doc
  end

  def fix_curl_highlighting(doc)
    doc.search('code').each do |node|
      next unless node.text.starts_with?('curl ')
    
      node.replace(node.to_html.gsub(/\{.*?\}/mi) {|uri_template|
        %(<span class="o">) + uri_template + %(</span>)
      })
    end

    doc
  end

  def add_code_filenames(doc)
    doc.search('./p').each do |node|
      next unless node.to_html.starts_with?('<p>{: codeblock-file=')

      filename = node.content[/codeblock-file="(.*)"}/, 1]

      figure = Nokogiri::XML::Node.new "figure", doc
      figure["class"] = "highlight-figure"
      caption = Nokogiri::XML::Node.new "figcaption", doc
      caption.content = filename
      figure.add_child(caption)
      node.previous_element.add_child(figure)

      node.previous_element.first_element_child.parent = figure
      node.remove
    end
    
    doc
  end

  def add_custom_ids(doc)
    doc.search('./p').each do |node|
      next unless node.to_html.starts_with?('<p>{: id=')

      id = node.content[/id="(.*)"}/, 1]

      node.previous_element['id'] = id
      node.remove
    end
    
    doc
  end
  
  def add_custom_classes(doc)
    doc.search('./p').each do |node|
      next unless node.to_html.starts_with?('<p>{: class=')

      css_class = node.content[/class="(.*)"}/, 1]

      node.previous_element['class'] = css_class
      node.remove
    end
    
    doc
  end
end
