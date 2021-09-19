{ config, lib, pkgs, ... }:

let
  makewhatis = "${lib.getBin pkgs.mandoc}/bin/makewhatis";

  cfg = config.documentation.man.mandoc;

in {
  meta.maintainers = [ lib.maintainers.sternenseemann ];

  options = {
    documentation.man.mandoc = {
      enable = lib.mkEnableOption "mandoc as the default man page viewer";

      manPath = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "share/man" ];
        example = lib.literalExpression "[ \"share/man\" \"share/man/fr\" ]";
        description = ''
          Change the manpath, i. e. the directories where
          <citerefentry><refentrytitle>man</refentrytitle><manvolnum>1</manvolnum></citerefentry>
          looks for section-specific directories of man pages.
          You only need to change this setting if you want extra man pages
          (e. g. in non-english languages). All values must be strings that
          are a valid path from the target prefix (without including it).
          The first value given takes priority.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment = {
      systemPackages = [ pkgs.mandoc ];

      # tell mandoc about man pages
      etc."man.conf".text = lib.concatMapStrings (path: ''
        manpath /run/current-system/sw/${path}
      '') cfg.manPath;

      # create mandoc.db for whatis(1), apropos(1) and man(1) -k
      # TODO(@sternenseemman): fix symlinked directories not getting indexed,
      # see: https://inbox.vuxu.org/mandoc-tech/20210906171231.GF83680@athene.usta.de/T/#e85f773c1781e3fef85562b2794f9cad7b2909a3c
      extraSetup = lib.mkIf config.documentation.man.generateCaches ''
        ${makewhatis} -T utf8 ${
          lib.concatMapStringsSep " " (path: "\"$out/${path}\"") cfg.manPath
        }
      '';
    };
  };
}
