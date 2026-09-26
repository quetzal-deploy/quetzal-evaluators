# TODO:
# - ask for sudo password (requires dynamic prompting in the front ends
# - health checks
# - pre deploy checks
# - check-health
# - upload-secrets
# - list-secrets
# - execute

let
  lib = rec {
    addDependencies = deps: step: step // { dependencies = (step.dependencies ++ deps); };
    addDependency = dep: step: addDependencies [ dep ] step;

    addSteps = newSteps: step: step // { steps = step.steps ++ newSteps; };
    addStep = newStep: step: addSteps [ newStep ] step;

    addLabels = newLabels: step: step // { labels = step.labels // newLabels; };

    id = i: step: step // { id = i; };
    description = d: step: step // { description = d; };
    action = a: step: step // { action = a; };

    parallel =
      step:
      step
      // {
        parallel = true;
      };
    sequential =
      step:
      step
      // {
        parallel = false;
      };

    skip =
      step: step // { steps = [ ]; } |> description "skipped: ${step.description}" |> action "none";

    onFailure = rec {
      _raw = q: { "on-failure" = q; };
      exit = step: step // (_raw "exit");
      nothing = step: step // (_raw "");
      retry = interval: step: step // (_raw "retry") // { "retry-interval" = interval; };
    };

    steps = {
      new =
        attrs:
        {
          description = "";
          action = "none";
          parallel = false;
          steps = [ ];
          "on-failure" = "";
          dependencies = [ ];
          "can-resume" = true;
          timeout = 0;
          "retry-interval" = 0;
          labels = { };
        }
        // attrs;

      build =
        hosts:
        steps.new { inherit hosts; }
        |> id "build"
        |> description "build hosts"
        |> action "build"
        |> onFailure.exit;

      push =
        host:
        steps.new { inherit host; }
        |> id "push:${host}"
        |> description "push to ${host}"
        |> action "push"
        |> onFailure.exit;

      deploy =
        action_: host:
        steps.new { inherit host; }
        |> id "deploy:${host}"
        |> description "deploy ${host}"
        |> action "deploy-${action_}"
        |> onFailure.nothing;

      deployBoot = steps.deploy "boot";
      deployDryActivate = steps.deploy "dry-activate";
      deploySwitch = steps.deploy "switch";
      deployTest = steps.deploy "test";

      reboot =
        host:
        steps.new { inherit host; }
        |> id "reboot:${host}"
        |> description "reboot ${host}"
        |> action "reboot";

      waitForOnline =
        host:
        steps.new { inherit host; }
        |> description "wait for ${host} to come online"
        |> action "is-online"
        |> onFailure.retry 2;

      # FIXME: Actually implement generating health checks as sub steps
      checkHealth =
        { host, checks }:
        steps.new { inherit host; } |> description "run checks for ${host}" |> action "none";
    };

    logic = rec {
      when =
        conditional: mergeAble: step:
        if conditional then step |> mergeAble else step;

      "if " = when;
    };

    mkHostSpecificPlan =
      {
        action,
        host,
        reboot,
        healthChecks,
        _meta,
      }:
      let
        push = steps.push host;
        rebootStep = logic.when reboot (addStep (steps.reboot host));
        wait = steps.waitForOnline host;
        preDeployChecks = steps.checkHealth {
          inherit host;
          checks = preDeployChecks;
        };
        healthChecks = steps.checkHealth {
          inherit host;
          checks = healthChecks;
        };

        step =
          steps.new { }
          |> id "host:${host}"
          |> description "host: ${host}"
          |> addLabels {
            inherit host;
            "_" = "host";
            type = "host";
          }
          |> addLabels _meta.hosts."${host}".labels # doing to calls to addLabels ensures that any host label will override default labels
          |> sequential
          |> addStep push;

        actions = {
          push = step;
          dry-activate = step |> addStep (steps.deployDryActivate host);
          test = step |> addStep preDeployChecks |> addStep (steps.deployTest host) |> addStep healthChecks;
          boot = step |> addStep (steps.deployBoot host) |> rebootStep;

          switch =
            step
            |> addStep preDeployChecks
            |> addStep (steps.deploySwitch host)
            |> rebootStep
            |> addStep wait # FIXME: Only needed if rebooting
            |> addStep healthChecks;
        };

      in
      actions."${action}";

    mkEmptyPlan =
      action: quetzalOptions: hosts:
      (steps.new { } |> id "root" |> description "Root of execution plan" |> parallel);

    mkDefaultBuildPlan =
      opts@{ hosts, ... }: mkEmptyPlan "a" "b" "c" |> addSteps ([ (steps.build hosts) ]);

    mkDefaultDeployPlan =
      opts@{
        action,
        hosts,
        reboot ? false,
        _meta,
        ...
      }:
      let
        build = steps.build opts;

        hostSpecificPlans = map (
          host:
          mkHostSpecificPlan ({
            inherit action host reboot _meta;
            healthChecks = [ ];
          })
          |> addDependency build.id
        ) hosts;
      in
      mkDefaultBuildPlan opts |> addSteps hostSpecificPlans;
  };

in
{
  inherit lib;

  plans = {
    build = lib.mkDefaultBuildPlan;
    push = args: lib.mkDefaultDeployPlan (args // { action = "push"; });
    boot = args: lib.mkDefaultDeployPlan (args // { action = "boot"; });
    dry-activate = args: lib.mkDefaultDeployPlan (args // { action = "dry-activate"; });
    switch = args: lib.mkDefaultDeployPlan (args // { action = "switch"; });
    test = args: lib.mkDefaultDeployPlan (args // { action = "test"; });
  };
}
