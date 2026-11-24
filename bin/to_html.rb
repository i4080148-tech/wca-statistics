#!/usr/bin/env ruby
# Converts the generated build/*.md files into a browsable site in site/.
# No extra gems needed. Open site/index.html in any browser.

require "fileutils"

root = File.expand_path("..", __dir__)
build_path = File.join(root, "build")
site_path = File.join(root, "site")
FileUtils.mkdir_p(site_path)

STYLE = <<~CSS
  body { font-family: -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; max-width: 1100px; margin: 2rem auto; padding: 0 1rem; color: #222; }
  table { border-collapse: collapse; margin: 1rem 0; font-size: 14px; }
  th, td { border: 1px solid #ddd; padding: 4px 8px; }
  th { background: #f4f4f4; }
  tr:nth-child(even) td { background: #fafafa; }
  a { color: #0b62c4; }
CSS

def inline(text)
  # Keep the few HTML bits the statistics emit (<br />, &nbsp;), escape the rest.
  t = text.gsub("&nbsp;", "\u0001").gsub("<br />", "\u0002")
  t = t.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  t = t.gsub("\u0001", "&nbsp;").gsub("\u0002", "<br />")
  t = t.gsub(/\[([^\]]*)\]\(([^)\s]+)\)/) do
    label, url = $1, $2
    url = "#{url}.html" if url =~ /\A[a-z0-9_]+\z/ # links between statistics pages
    %(<a href="#{url.gsub('"', '%22')}">#{label}</a>)
  end
  t = t.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
  t.gsub(/(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])/, '<em>\1</em>')
end

def cells(line)
  line.strip.sub(/\A\|/, "").sub(/\|\z/, "").split("|").map(&:strip)
end

def to_html(markdown)
  lines = markdown.lines.map(&:chomp)
  out = []
  i = 0
  while i < lines.size
    line = lines[i]
    if line =~ /\A(#+)\s+(.*)/
      level = [$1.size, 6].min
      out << "<h#{level}>#{inline($2)}</h#{level}>"
      i += 1
    elsif line.start_with?("|") && lines[i + 1].to_s =~ /\A\|\s*:?-+/
      header = cells(line)
      aligns = cells(lines[i + 1]).map do |c|
        c.start_with?(":") && c.end_with?(":") ? "center" : c.end_with?(":") ? "right" : "left"
      end
      out << "<table><thead><tr>" + header.each_with_index.map { |h, k| %(<th style="text-align:#{aligns[k]}">#{inline(h)}</th>) }.join + "</tr></thead><tbody>"
      i += 2
      while i < lines.size && lines[i].start_with?("|")
        out << "<tr>" + cells(lines[i]).each_with_index.map { |c, k| %(<td style="text-align:#{aligns[k] || 'left'}">#{inline(c)}</td>) }.join + "</tr>"
        i += 1
      end
      out << "</tbody></table>"
    elsif line =~ /\A[-*]\s+(.*)/
      out << "<ul>"
      while i < lines.size && lines[i] =~ /\A[-*]\s+(.*)/
        out << "<li>#{inline($1)}</li>"
        i += 1
      end
      out << "</ul>"
    elsif line.strip.empty?
      i += 1
    elsif line.strip.start_with?("<")
      i += 1 # skip raw HTML snippets such as the GitHub corner
    else
      out << "<p>#{inline(line)}</p>"
      i += 1
    end
  end
  out.join("\n")
end

Dir.glob(File.join(build_path, "*.md")).each do |md_file|
  name = File.basename(md_file, ".md")
  out_name = name == "README" ? "index" : name
  body = to_html(File.read(md_file))
  back = out_name == "index" ? "<h1>WCA Statistics</h1>" : %(<p><a href="index.html">&larr; All statistics</a></p>)
  title = out_name == "index" ? "WCA Statistics" : name.tr("_", " ")
  File.write(File.join(site_path, "#{out_name}.html"), <<~HTML)
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><title>#{title}</title><style>#{STYLE}</style></head>
    <body>#{back}
    #{body}
    </body></html>
  HTML
end
puts "Site generated in #{site_path} (open index.html)"
