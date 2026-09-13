# Used by "mix format"

exported_locals_without_parens = [
  belongs_to: 2,
  belongs_to: 3,
  has_many: 2,
  has_many: 3,
  has_one: 2,
  has_one: 3
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: exported_locals_without_parens,
  export: [locals_without_parens: exported_locals_without_parens]
]
