{ ... }:

{
  environment.etc."xdg/kcminputrc".text = ''
    [Libinput][Defaults][Touchpad]
    NaturalScroll=true
    ClickMethod=2
  '';
}
