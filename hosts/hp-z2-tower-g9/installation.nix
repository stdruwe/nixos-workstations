{ ... }:

{
  # Installation uses the complete host base but intentionally omits
  # Lanzaboote/Secure Boot until the first successful boot.
  imports = [
    ./base.nix
  ];
}
