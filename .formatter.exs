# Used by "mix format"
[
  plugins: [Styler],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  subdirectories: ["test/support"],
  locals_without_parens: [
    description: 1,
    tool: 2
  ],
  export: [
    locals_without_parens: [
      description: 1,
      tool: 2
    ]
  ]
]
