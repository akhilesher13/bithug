module Project
  class Routes < Monk::Glue

    get '/' do
      require 'rdoc/markup/to_html'
      h = RDoc::Markup::ToHtml.new
      src = h.convert(File.read(root_path("README.rdoc")))
      haml :home, {}, :rdoc => src
    end

  end
end