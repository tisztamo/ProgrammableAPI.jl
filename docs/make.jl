using Documenter, ProgrammableAPI

makedocs(
    modules = [ProgrammableAPI],
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true"),
    authors = "Schäffer Krisztián",
    sitename = "ProgrammableAPI.jl",
    pages = Any["index.md"]
    # strict = true,
    # clean = true,
    # checkdocs = :exports,
)

deploydocs(
    repo = "github.com/tisztamo/ProgrammableAPI.jl.git",
    push_preview = true
)
