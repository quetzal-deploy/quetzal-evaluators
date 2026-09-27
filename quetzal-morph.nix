# calling this: nix-instantiate --eval --strict --json data/plan-wrapper.nix --arg hosts '["zebra" "elephant"]' --argstr flakePath "/home/adtu/src/quetzal-deployment"
# TODO: consider renaming to something like flake-deployment-wrapper.nix
{
  deployment,
}:

let
  flake = builtins.getFlake /home/adtu/deployments;
  wrapper = import ./morph/eval-machines.nix {
    # networkExpr = deployment;
    network = flake.morphDeployments.tools;
  };

  setCheckType = type: check: check // { inherit type; };
  convertHttpCheck = host: check: {
    inherit (check) description headers insecureSSL timeout;
    type = "local-request"; # only request type supported by morph

    url = let
      scheme = check.scheme;
      address = if check.host != null then check.host else host.targetHost;
      port = if check.port != null then ":${toString check.port}" else "";
      path = check.path;
    in "${scheme}://${address}${port}${path}";
  };

  convertChecks = host: checks:
    (map (setCheckType "remote-command") checks.cmd) ++
    (map (convertHttpCheck host) checks.http);

  quetzalHost = h: {
    inherit (h) name labels;

    # If the morph host is build only then set address explicitly to null
    address = if h.buildOnly then null else h.targetHost;

    ssh = {
      # morph likes setting targetUser to "" => replace that with null
      user = if h.targetUser != "" then h.targetUser else null;
      port = h.targetPort;
    };

    nix = {
      config = h.nixConfig or {};
    };

    nixos = {
      release = h.nixosRelease;
    };

    checks = {
      before  = convertChecks h h.preDeployChecks;
      after  = convertChecks h h.healthChecks;
    };
  };

  quetzalHosts = map quetzalHost wrapper.info.deployment.hosts;

in {
  resources = {
    hosts = builtins.listToAttrs ( map (host: { name = host.name; value = host; }) quetzalHosts);
    inputs = {};
  };

  build = { args ? null}:
    let
      args' = if args != null then builtins.fromJSON (builtins.readFile args) else { };
    in
      wrapper.machines {
        argsFile = builtins.toFile "morph-args-file.json" (builtins.toJSON { Names = args'.hosts; });
      };

  # plans2 = builtins.attrNames wrapper.network.plans;
  plans2 =
  let
    planner = import ./planner.nix;
  in
    builtins.attrNames planner.plans;

  plans =
    {
      plan,
      args ? null,
      ...
    }:
    let
      planner = import ./planner.nix;
      args' = if args != null then builtins.fromJSON (builtins.readFile args) else { };
    in
    {
      # Look up the requested $plan first in the deployment, and then fall back to what's provided by Quetzal
      plan = (wrapper.network.plans."${plan}" or planner.plans."${plan}") args';
      # plan = wrapper.network.plans."${plan}" args';
      constraints = wrapper.info.deployment.meta.constraints;
    };
}
