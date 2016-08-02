module CustomEncodings
  module Marc21
    class Constants
      TAGS = {}
      TAGS["110"] = { "*" => "author" }
      TAGS["245"] = { "*" => "title" }
      TAGS["300"] = { "*" => "description" }
      TAGS["520"] = { "*" => "abstract" }
      TAGS["546"] = { "*" => "language" }
      TAGS["600"] = { "*" => "subject" }
      TAGS["650"] = { "a" => "subject",
        "z" => "coverage"
      }
      TAGS["651"] = { "a" => "coverage",
        "x" => "subject",
        "y" => "date",
        "z" => "coverage"
      }
    end
  end
end