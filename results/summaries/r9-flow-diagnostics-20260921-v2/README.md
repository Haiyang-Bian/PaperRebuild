# R9 continuous-flow development diagnostics

Five frozen probes use the same synthetic 44/38-node, 24-hour input and an explicitly
declared CF-CT physical witness as the initial point of an independent direct reference.
No probe returned an accepted solution. These are not projected-gradient results,
infeasibility proofs, cost-saving measurements, or a completed four-mode comparison.

Each original manifest and its listed input/source files are preserved byte for byte.
Solver logs are public copies with workspace paths and license metadata removed;
index.toml retains original and public hashes. Original local logs are unchanged.
Solver iteration residuals have the solver's own scaling and are not independent A1 checks.

Recheck without Gurobi or the private thesis:
`julia +1.12.6 --startup-file=no --project=. scripts/r9_flow_diagnostics.jl check PATH`
