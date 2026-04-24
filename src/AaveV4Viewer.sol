// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct SpokeDescriptor {
  string name;
  address addr;
}

contract AaveV4Viewer {
  /// @dev Known Spokes on Ethereum Mainnet
  SpokeDescriptor[11] deployedSpokes = [
    SpokeDescriptor('Main Spoke', 0x94e7A5dCbE816e498b89aB752661904E2F56c485),
    SpokeDescriptor(
      'Bluechip Spoke',
      0x973a023A77420ba610f06b3858aD991Df6d85A08
    ),
    SpokeDescriptor(
      'Ethena Correlated Spoke',
      0x58131E79531caB1d52301228d1f7b842F26B9649
    ),
    SpokeDescriptor(
      'Ethena Ecosystem Spoke',
      0xba1B3D55D249692b669A164024A838309B7508AF
    ),
    SpokeDescriptor(
      'EtherFi eSpoke',
      0xbF10BDfE177dE0336aFD7fcCF80A904E15386219
    ),
    SpokeDescriptor('Forex Spoke', 0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1),
    SpokeDescriptor('Gold Spoke', 0x65407b940966954b23dfA3caA5C0702bB42984DC),
    SpokeDescriptor('Kelp eSpoke', 0x3131FE68C4722e726fe6B2819ED68e514395B9a4),
    SpokeDescriptor('Lido eSpoke', 0xe1900480ac69f0B296841Cd01cC37546d92F35Cd),
    SpokeDescriptor(
      'Lombard BTC Spoke',
      0x7EC68b5695e803e98a21a9A05d744F28b0a7753D
    ),
    SpokeDescriptor(
      'Treasury Spoke',
      0xB9B0b8616f6Bf6841972a52058132BE08d723155
    )
  ];
}
