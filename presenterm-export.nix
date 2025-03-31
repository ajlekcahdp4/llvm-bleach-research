{
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  ansi2html,
  libtmux,
  weasyprint,
  dataclass-wizard,
}:

buildPythonPackage rec {
  pname = "presenterm-export";
  version = "0.2.7";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mfontanini";
    repo = "presenterm-export";
    tag = "v${version}";
    hash = "sha256-aa1Og8wl1dwnMUkQ/1bQ+LHCsXQWKnHSsJmpUkCGEdg=";
  };

  build-system = [ setuptools ];

  dependencies = [
    ansi2html
    libtmux
    weasyprint
    dataclass-wizard
  ];

  pythonRelaxDeps = [
    "ansi2html"
    "libtmux"
    "weasyprint"
    "dataclass-wizard"
  ];
}
