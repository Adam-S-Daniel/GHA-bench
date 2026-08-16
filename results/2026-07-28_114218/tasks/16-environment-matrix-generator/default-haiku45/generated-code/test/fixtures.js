// Test fixtures for matrix generator

export const fixtures = {
  // Simple 2x2 matrix
  simple: {
    config: {
      os: ['ubuntu-latest', 'macos-latest'],
      node_version: ['18', '20']
    },
    options: {},
    expectedSize: 4
  },

  // Single-dimension matrix
  singleDimension: {
    config: {
      node_version: ['16', '18', '20']
    },
    options: {},
    expectedSize: 3
  },

  // Three-dimensional matrix
  threeDimensions: {
    config: {
      os: ['ubuntu-latest', 'macos-latest'],
      node_version: ['18', '20'],
      arch: ['x64', 'arm64']
    },
    options: {},
    expectedSize: 8
  },

  // Matrix with excludes
  withExcludes: {
    config: {
      os: ['ubuntu-latest', 'macos-latest'],
      node_version: ['18', '20']
    },
    options: {
      exclude: [
        { os: 'macos-latest', node_version: '18' }
      ]
    },
    expectedSize: 3
  },

  // Matrix with includes
  withIncludes: {
    config: {
      os: ['ubuntu-latest'],
      node_version: ['18']
    },
    options: {
      include: [
        { os: 'windows-latest', node_version: '20' },
        { os: 'ubuntu-latest', node_version: '22' }
      ]
    },
    expectedSize: 3
  },

  // Complex case: includes and excludes together
  complex: {
    config: {
      os: ['ubuntu-latest', 'macos-latest'],
      node_version: ['18', '20']
    },
    options: {
      exclude: [
        { os: 'macos-latest', node_version: '18' }
      ],
      include: [
        { os: 'windows-latest', node_version: '20', custom: 'value' }
      ]
    },
    expectedSize: 4
  }
};

export const expectedMatrices = {
  simple: {
    include: [
      { os: 'ubuntu-latest', node_version: '18' },
      { os: 'ubuntu-latest', node_version: '20' },
      { os: 'macos-latest', node_version: '18' },
      { os: 'macos-latest', node_version: '20' }
    ]
  },

  singleDimension: {
    include: [
      { node_version: '16' },
      { node_version: '18' },
      { node_version: '20' }
    ]
  },

  threeDimensions: {
    include: [
      { os: 'ubuntu-latest', node_version: '18', arch: 'x64' },
      { os: 'ubuntu-latest', node_version: '18', arch: 'arm64' },
      { os: 'ubuntu-latest', node_version: '20', arch: 'x64' },
      { os: 'ubuntu-latest', node_version: '20', arch: 'arm64' },
      { os: 'macos-latest', node_version: '18', arch: 'x64' },
      { os: 'macos-latest', node_version: '18', arch: 'arm64' },
      { os: 'macos-latest', node_version: '20', arch: 'x64' },
      { os: 'macos-latest', node_version: '20', arch: 'arm64' }
    ]
  }
};
