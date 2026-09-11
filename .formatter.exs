# Used by "mix format"

exported_locals_without_parens = [
  loader: 1,
  belongs_to: 2,
  belongs_to: 3,
  has_many: 2,
  has_many: 3
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [assert_lists: 2] ++ exported_locals_without_parens,
  export: [locals_without_parens: exported_locals_without_parens]
]
