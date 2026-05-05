from __future__ import annotations

import subprocess
from enum import StrEnum
from pathlib import Path

import pytest


class FvsVariant(StrEnum):
    """Enumeration of supported FVS Variants."""

    AK = "AK"  # Southeast Alaska and Coastal British Columbia
    # BC = "BC"  # British Columbia
    BM = "BM"  # Blue Mountains
    CA = "CA"  # Inland California and Southern Cascades (ICASCA)
    CI = "CI"  # Central Idaho
    CR = "CR"  # Central Rockies
    CS = "CS"  # Central States
    EC = "EC"  # East Cascades
    EM = "EM"  # Eastern Montana
    IE = "IE"  # Inland Empire
    KT = "KT"  # Kootenai, Kaniksu, and Tally Lake (KooKanTL)
    LS = "LS"  # Lake States
    NC = "NC"  # Klamath Mountains (and northern California)
    NE = "NE"  # Northeastern US
    OC = "OC"  # Organon Southwest
    # ON = "ON"  # Ontario
    OP = "OP"  # Organon Pacific Northwest
    PN = "PN"  # Pacific Northwest Coast
    SN = "SN"  # Southern US
    SO = "SO"  # South Central Oregon and Northeast California (SORNEC)
    TT = "TT"  # Tetons
    UT = "UT"  # Utah
    WC = "WC"  # Westside Cascades
    WS = "WS"  # Western Sierra Nevada


KEYFILES_DIR = Path(__file__).parent / "keyfiles"


@pytest.mark.parametrize("variant", FvsVariant)
def test_fvs_build(variant: FvsVariant, tmp_path: Path) -> None:
    """
    Confirm each FVS regional variant runs a simple keyfile without warnings or errors.

    Requires FVS binaries on PATH at /usr/local/bin/FVS<region> (e.g. FVSak).
    """
    fvs = Path("/usr/local/bin") / f"FVS{variant.lower()}"
    keyfile = tmp_path / f"{variant}_buildtest.key"
    keyfile.write_text((KEYFILES_DIR / f"{variant}.key").read_text())
    outfile = tmp_path / f"{variant}_buildtest.out"
    proc = subprocess.run(
        [str(fvs), f"--keywordfile={keyfile}"],
        check=False,
    )

    assert keyfile.exists()
    assert outfile.exists()
    outdata = outfile.read_text()
    assert "WARNING:" not in outdata
    assert "ERROR:" not in outdata
    assert proc.returncode == 0
