# Nixpkgs/NixOS option handling.
{ lib }:

with lib.trivial;
with lib.lists;
with lib.attrsets;
with lib.strings;

rec {

  # Returns true when the given argument is an option
  #
  # Examples:
  #   isOption 1             // => false
  #   isOption (mkOption {}) // => true
  isOption = lib.isType "option";

  # Creates an Option attribute set. mkOption accepts an attribute set with the following keys:
  #
  #  default:     Default value used when no definition is given in the configuration.
  #  defaultText: Textual representation of the default, for in the manual.
  #  example:     Example value used in the manual.
  #  description: String describing the option.
  #  type:        Option type, providing type-checking and value merging.
  #  apply:       Function that converts the option value to something else.
  #  internal:    Whether the option is for NixOS developers only.
  #  visible:     Whether the option shows up in the manual.
  #  readOnly:    Whether the option can be set only once
  #  options:     Obsolete, used by types.optionSet.
  #
  # All keys default to `null` when not given.
  #
  # Examples:
  #   mkOption { }  // => { _type = "option"; }
  #   mkOption { defaultText = "foo"; } // => { _type = "option"; defaultText = "foo"; }
  mkOption =
    { default ? null # Default value used when no definition is given in the configuration.
    , defaultText ? null # Textual representation of the default, for in the manual.
    , example ? null # Example value used in the manual.
    , description ? null # String describing the option.
    , relatedPackages ? null # Related packages used in the manual (see `genRelatedPackages` in ../nixos/doc/manual/default.nix).
    , type ? null # Option type, providing type-checking and value merging.
    , apply ? null # Function that converts the option value to something else.
    , internal ? null # Whether the option is for NixOS developers only.
    , visible ? null # Whether the option shows up in the manual.
    , readOnly ? null # Whether the option can be set only once
    , options ? null # Obsolete, used by types.optionSet.
    } @ attrs:
    attrs // { _type = "option"; };

  # Creates a Option attribute set for a boolean value option i.e an option to be toggled on or off:
  #
  # Examples:
  #   mkEnableOption "foo" // => { _type = "option"; default = false; description = "Whether to enable foo."; example = true; type = { ... }; }
  mkEnableOption = name: mkOption {
    default = false;
    example = true;
    description = "Whether to enable ${name}.";
    type = lib.types.bool;
  };

  # This option accept anything, but it does not produce any result.  This
  # is useful for sharing a module across different module sets without
  # having to implement similar features as long as the value of the options
  # are not expected.
  mkSinkUndeclaredOptions = attrs: mkOption ({
    internal = true;
    visible = false;
    default = false;
    description = "Sink for option definitions.";
    type = mkOptionType {
      name = "sink";
      check = x: true;
      merge = loc: defs: false;
    };
    apply = x: throw "Option value is not readable because the option is not declared.";
  } // attrs);

  mergeDefaultOption = loc: defs:
    let list = getValues defs; in
    if length list == 1 then head list
    else if all isFunction list then x: mergeDefaultOption loc (map (f: f x) list)
    else if all isList list then concatLists list
    else if all isAttrs list then foldl' lib.mergeAttrs {} list
    else if all isBool list then foldl' lib.or false list
    else if all isString list then lib.concatStrings list
    else if all isInt list && all (x: x == head list) list then head list
    else throw "Cannot merge definitions of `${showOption loc}' given in ${showFiles (getFiles defs)}.";

  mergeOneOption = loc: defs:
    if defs == [] then abort "This case should never happen."
    else if length defs != 1 then
      throw "The unique option `${showOption loc}' is defined multiple times, in ${showFiles (getFiles defs)}."
    else (head defs).value;

  /* "Merge" option definitions by checking that they all have the same value. */
  mergeEqualOption = loc: defs:
    if defs == [] then abort "This case should never happen."
    else foldl' (val: def:
      if def.value != val then
        throw "The option `${showOption loc}' has conflicting definitions, in ${showFiles (getFiles defs)}."
      else
        val) (head defs).value defs;

  # Extracts values of all "value" keys of the given list
  #
  # Examples:
  #   getValues [ { value = 1; } { value = 2; } ] // => [ 1 2 ]
  #   getValues [ ]                               // => [ ]
  getValues = map (x: x.value);

  # Extracts values of all "file" keys of the given list
  #
  # Examples:
  #   getFiles [ { file = "file1"; } { file = "file2"; } ] // => [ "file1" "file2" ]
  #   getFiles [ ]                                         // => [ ]
  getFiles = map (x: x.file);

  # Generate documentation template from the list of option declaration like
  # the set generated with filterOptionSets.
  optionAttrSetToDocList = optionAttrSetToDocList' [];

  optionAttrSetToDocList' = prefix: options:
    concatMap (opt:
      let
        docOption = rec {
          loc = opt.loc;
          name = showOption opt.loc;
          description = opt.description or (throw "Option `${name}' has no description.");
          declarations = filter (x: x != unknownModule) opt.declarations;
          internal = opt.internal or false;
          visible = opt.visible or true;
          readOnly = opt.readOnly or false;
          type = opt.type.description or null;
        }
        // optionalAttrs (opt ? example) { example = scrubOptionValue opt.example; }
        // optionalAttrs (opt ? default) { default = scrubOptionValue opt.default; }
        // optionalAttrs (opt ? defaultText) { default = opt.defaultText; }
        // optionalAttrs (opt ? relatedPackages && opt.relatedPackages != null) { inherit (opt) relatedPackages; };

        subOptions =
          let ss = opt.type.getSubOptions opt.loc;
          in if ss != {} then optionAttrSetToDocList' opt.loc ss else [];
      in
        [ docOption ] ++ subOptions) (collect isOption options);


  /* This function recursively removes all derivation attributes from
     `x' except for the `name' attribute.  This is to make the
     generation of `options.xml' much more efficient: the XML
     representation of derivations is very large (on the order of
     megabytes) and is not actually used by the manual generator. */
  scrubOptionValue = x:
    if isDerivation x then
      { type = "derivation"; drvPath = x.name; outPath = x.name; name = x.name; }
    else if isList x then map scrubOptionValue x
    else if isAttrs x then mapAttrs (n: v: scrubOptionValue v) (removeAttrs x ["_args"])
    else x;


  /* For use in the ‘example’ option attribute.  It causes the given
     text to be included verbatim in documentation.  This is necessary
     for example values that are not simple values, e.g.,
     functions. */
  literalExample = text: { _type = "literalExample"; inherit text; };


  /* Helper functions. */

  # Convert an option, described as a list of the option parts in to a
  # safe, human readable version. ie:
  #
  # (showOption ["foo" "bar" "baz"]) == "foo.bar.baz"
  # (showOption ["foo" "bar.baz" "tux"]) == "foo.\"bar.baz\".tux"
  showOption = parts: let
    escapeOptionPart = part:
      let
        escaped = lib.strings.escapeNixString part;
      in if escaped == "\"${part}\""
         then part
         else escaped;
    in (concatStringsSep ".") (map escapeOptionPart parts);
  showFiles = files: concatStringsSep " and " (map (f: "`${f}'") files);
  unknownModule = "<unknown-file>";

}
