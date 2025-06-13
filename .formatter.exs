# Used by "mix format"
[
  plugins: [Styler],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  subdirectories: ["test/support"],
  export: [
    locals_without_parens: [
      # Add any custom DSL functions here
    ]
  ]
]
