using PaperRebuild, JuMP
for file in ("single-source", "two-source")
    c = load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", file*".toml"))
    for form in (:wmm_checked_v1, :schpd_mc_v1), fixed in (false, true)
        b = build_r2_model(c; spec = R2Spec(; formulation = form), fixed_flows = fixed)
        println(
            file,
            " ",
            form,
            " fixed=",
            fixed,
            " class=",
            b.class,
            " variables=",
            num_variables(b.model),
        )
    end
end
