using Documenter, ForthAPI

makedocs(
    modules = [ForthAPI],
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true"),
    authors = "Schäffer Krisztián",
    sitename = "ForthAPI.jl",
    pages = Any["index.md"]
    # strict = true,
    # clean = true,
    # checkdocs = :exports,
)

deploydocs(
    repo = "github.com/tisztamo/ForthAPI.jl.git",
    push_preview = true
)
