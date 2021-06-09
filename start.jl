# - Include this file from the repl and use `@run`
# - Or run circonode.sh -s start.jl -z

using Circo, ForthAPI

zygote(ctx) = []
plugins() = [ForthAPI.WSAPIService, Debug.MsgStats]
options() = (wsapi_managerfactory = ForthAPI.manager,)
profile(;opts...) = Circo.Profiles.ClusterProfile(;opts...)

macro run()
    return Circo.cli.runnerquote()
end