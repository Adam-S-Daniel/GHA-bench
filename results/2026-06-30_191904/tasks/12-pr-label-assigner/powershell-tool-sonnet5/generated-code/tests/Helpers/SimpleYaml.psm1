# SimpleYaml.psm1
# A deliberately minimal, dependency-free YAML reader covering just the
# subset GitHub Actions workflow files use: nested block mappings, block
# sequences (of scalars or mappings), quoted scalars, and block scalars
# (`key: |` / `key: >`, used for multi-line `run:` steps). It exists so the
# workflow-structure Pester tests don't need the powershell-yaml module,
# which isn't installed in the act container (only pwsh + Pester are).

function Convert-ScalarYamlValue {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $trimmed = $Text.Trim()
    if ($trimmed.Length -ge 2 -and (
        ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'")) -or
        ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"'))
        )) {
        return $trimmed.Substring(1, $trimmed.Length - 2)
    }
    return $trimmed
}

function Test-YamlLineSkippable {
    # Blank lines and full-line comments are structurally insignificant
    # everywhere EXCEPT inside a block scalar, which callers handle
    # separately by consuming raw lines directly.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line)
    $t = $Line.Trim()
    return ($t -eq '' -or $t.StartsWith('#'))
}

function Find-NextSignificantLine {
    # Peeks forward from $FromIndex (inclusive) to find the next
    # non-blank/non-comment line, skipping over ones that are. Returns a
    # hashtable with Index (-1 if none found), Indent, and Trimmed text.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory)]
        [int]$FromIndex
    )
    for ($j = $FromIndex; $j -lt $Lines.Count; $j++) {
        if (-not (Test-YamlLineSkippable -Line $Lines[$j])) {
            return @{
                Index   = $j
                Indent  = $Lines[$j].Length - $Lines[$j].TrimStart(' ').Length
                Trimmed = $Lines[$j].Trim()
            }
        }
    }
    return @{ Index = -1; Indent = -1; Trimmed = $null }
}

function Read-YamlValue {
    <#
    Interprets the text after a 'key:' (or '- key:') marker. If it's a
    block-scalar indicator ('|', '|-', '>', etc.), consumes the following
    more-indented raw lines as a single joined string. Otherwise returns the
    plain scalar. Returns @{ IsBlock; Value; NextIndex }; NextIndex is where
    the caller's cursor should resume.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$RawValue,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory)]
        [int]$StartIndex,
        [Parameter(Mandatory)]
        [int]$KeyIndent
    )

    if ($RawValue.Trim() -notmatch '^[|>][+-]?$') {
        return @{ IsBlock = $false; Value = (Convert-ScalarYamlValue -Text $RawValue); NextIndex = $StartIndex }
    }

    $contentLines = [System.Collections.Generic.List[string]]::new()
    $baseIndent = -1
    $idx = $StartIndex
    while ($idx -lt $Lines.Count) {
        $line = $Lines[$idx]
        if ($line.Trim() -eq '') {
            $contentLines.Add('')
            $idx++
            continue
        }
        $lineIndent = $line.Length - $line.TrimStart(' ').Length
        if ($lineIndent -le $KeyIndent) { break }
        if ($baseIndent -eq -1) { $baseIndent = $lineIndent }
        $strip = [Math]::Min($baseIndent, $lineIndent)
        $contentLines.Add($line.Substring($strip))
        $idx++
    }
    # Trim trailing blank lines (block-scalar clip/strip chomping).
    while ($contentLines.Count -gt 0 -and $contentLines[$contentLines.Count - 1] -eq '') {
        $contentLines.RemoveAt($contentLines.Count - 1)
    }

    return @{ IsBlock = $true; Value = ($contentLines -join "`n"); NextIndex = $idx }
}

function New-YamlChildContainer {
    # Decides whether an empty-valued key becomes a nested mapping or a
    # sequence, based on the next significant line's shape.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory)]
        [int]$FromIndex,
        [Parameter(Mandatory)]
        [int]$MinIndent
    )
    $next = Find-NextSignificantLine -Lines $Lines -FromIndex $FromIndex
    if ($next.Index -ge 0 -and $next.Indent -ge $MinIndent -and ($next.Trimmed.StartsWith('- ') -or $next.Trimmed -eq '-')) {
        # The leading comma prevents PowerShell from unrolling the (often
        # empty) List onto the output pipeline, which would otherwise
        # collapse it to $null and silently discard the container.
        return , [System.Collections.Generic.List[object]]::new()
    }
    return [ordered]@{}
}

function ConvertFrom-SimpleYaml {
    <#
    Parses an array of YAML lines (2-space indentation, no flow-style
    collections) into nested [ordered] hashtables / arrays, with block
    scalars ('key: |') read as single joined strings. Returns an [ordered]
    hashtable representing the document root.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $root = [ordered]@{}
    $stack = [System.Collections.Generic.List[object]]::new()
    $stack.Add(@{ Indent = -1; Node = $root })

    $i = 0
    while ($i -lt $Lines.Count) {
        $rawLine = $Lines[$i]
        if (Test-YamlLineSkippable -Line $rawLine) { $i++; continue }

        $indent = $rawLine.Length - $rawLine.TrimStart(' ').Length
        $line = $rawLine.Trim()

        while ($stack.Count -gt 1 -and $stack[$stack.Count - 1].Indent -ge $indent) {
            $stack.RemoveAt($stack.Count - 1)
        }
        $parent = $stack[$stack.Count - 1]

        if ($line.StartsWith('- ') -or $line -eq '-') {
            $itemText = if ($line -eq '-') { '' } else { $line.Substring(2) }
            if ($parent.Node -isnot [System.Collections.IList]) {
                throw "SimpleYaml parse error: sequence item found under a non-sequence key near '$line'"
            }

            if ($itemText -match '^([A-Za-z0-9_."''\-]+):\s*(.*)$') {
                $key = $matches[1].Trim('"''')
                $val = $matches[2]
                $itemMap = [ordered]@{}
                if ($val -eq '') {
                    $itemMap[$key] = New-YamlChildContainer -Lines $Lines -FromIndex ($i + 1) -MinIndent ($indent + 2)
                    $nextIndex = $i + 1
                }
                else {
                    $read = Read-YamlValue -RawValue $val -Lines $Lines -StartIndex ($i + 1) -KeyIndent ($indent + 2)
                    $itemMap[$key] = $read.Value
                    $nextIndex = $read.NextIndex
                }
                [void]$parent.Node.Add($itemMap)
                # Frame indent matches the '-' marker's own indent (mirroring
                # how regular mapping keys use their own line's indent) so a
                # sibling '- ...' item at the same indent correctly pops this
                # frame, while deeper-indented sibling keys (e.g. 'uses:'
                # under the same item) do not.
                $stack.Add(@{ Indent = $indent; Node = $itemMap })
                $i = $nextIndex
                continue
            }
            else {
                [void]$parent.Node.Add((Convert-ScalarYamlValue -Text $itemText))
                $i++
                continue
            }
        }

        if ($line -match '^([A-Za-z0-9_."''\-]+):\s*(.*)$') {
            $key = $matches[1].Trim('"''')
            $val = $matches[2]

            if ($val -eq '') {
                $parent.Node[$key] = New-YamlChildContainer -Lines $Lines -FromIndex ($i + 1) -MinIndent ($indent + 1)
                $stack.Add(@{ Indent = $indent; Node = $parent.Node[$key] })
                $i++
                continue
            }

            $read = Read-YamlValue -RawValue $val -Lines $Lines -StartIndex ($i + 1) -KeyIndent $indent
            $parent.Node[$key] = $read.Value
            $i = $read.NextIndex
            continue
        }

        throw "SimpleYaml parse error: could not parse line '$line'"
    }

    return $root
}

Export-ModuleMember -Function ConvertFrom-SimpleYaml, Convert-ScalarYamlValue
