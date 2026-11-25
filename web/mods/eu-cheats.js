/* Example cheat mod: community Game Genie codes for the EU release.
 * Sources: almarsguides.com / etherealgames.com / gamehacking.org (EU pages).
 * These are region-specific and NOT verified on hardware by this port -
 * enable selectively in the Cheats tab. Codes are applied by the core. */
(function () {
  BP.mods.register({
    id: 'eu-cheats',
    name: 'EU Game Genie pack',
    version: '1.0',
    author: 'community (see description)',
    description: 'Community-sourced Game Genie codes for the European release. Unverified - toggle individually in the Cheats tab. Adds codes to the cheat list; does not enable them.',
    enabledByDefault: true,
    cheats: [
      { code: 'AT4T-AA86', label: 'Infinite lives' },
      { code: 'AA5T-AAEA', label: 'Infinite energy (EU)' },
      { code: 'EZLT-CAFR', label: 'Start new game with 25 lives' },
      { code: 'BFLT-CAFR', label: 'Start new game with 9 lives' },
      { code: 'AD2A-AAFR', label: 'Infinite boogers' },
      { code: 'AD2T-AAFT', label: 'Infinite loogies (after milk)' },
      { code: 'ZCKA-ACH6', label: 'High jump' }
    ]
  });
})();
