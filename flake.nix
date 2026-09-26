{
  description = "Morph evaluator for Quetzal";

  outputs = { ... }: {
    lib = (import ./planner.nix).lib;
  };
}
