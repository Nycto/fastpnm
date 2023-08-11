runnableExamples:
    import std/[os, strformat]

    # converting an image to `.pbm` format via `convert` tool (I think it's part of `ImageMagick` app)
    discard execShellCmd fmt"convert -flatten -background white -alpha remove -resize 32x32 ./examples/arrow.png ./examples/play4.pbm"

    var pbm4 = parsePnm readFile "./examples/play4.pbm"
    assert pbm4.magic == P4
    assert pbm4.width == 32
    assert pbm4.height == 32
    assert pbm4.getBool(10, 10)
    assert not pbm4.getBool(0, 0)
    pbm4.magic = pbm4.magic.toUnCompressed
    assert pbm4.magic == P1

    writeFile "./examples/play1.pbm", $pbm4
    let pbm1 = parsePnm readFile "./examples/play1.pbm"
    assert pbm4.data == pbm1.data
    assert pbm4.width == pbm1.width
    assert pbm4.height == pbm1.height
    echo (pbm4.magic, pbm1.magic) 
    assert pbm1.magic == P1


import std/[strutils, parseutils, bitops, macros]

type
    PnmParserState = enum
        ppsMagic
        ppsWidth
        ppsHeight
        ppsMaxVal
        ppsContent

    PnmMagic* = enum
        bitMapRaw = "P1"
        grayMapRaw = "P2"
        pixMapRaw = "P3"
        bitMapBinray = "P4"
        grayMapBinray = "P5"
        pixMapBinray = "P6"

    Pnm* = object
        magic*: PnmMagic
        width*, height*, maxValue*: Natural
        comments*: seq[string]
        data*: seq[byte]

    Position* = tuple
        x, y: int

    Color* = tuple
        r, g, b: uint8

const
    P1* = bitMapRaw
    P2* = grayMapRaw
    P3* = pixMapRaw
    P4* = bitMapBinray
    P5* = grayMapBinray
    P6* = pixMapBinray

    bitMap* = {bitMapRaw, bitMapBinray}
    grayMap* = {grayMapRaw, grayMapBinray}
    pixMap* = {pixMapRaw, pixMapBinray}

    uncompressed* = {P1..P3}
    compressed* = {P4..P6}

# ----- meta utility

macro addMulti(wrapper: untyped, elems: varargs[untyped]): untyped =
    result = newStmtList()
    for e in elems:
        result.add quote do:
            `wrapper`.add `e`

template impossible =
    raise newException(ValueError, "I thought it was impossible")

# ----- private utility

func toDigit(b: bool): char =
    case b
    of true: '1'
    of false: '0'

iterator findInts(s: string, offset: int): int =
    var
        i = offset
    while i <= s.high:
        let ch = s[i]
        case ch
        of Whitespace: inc i
        of Digits:
            var n: int
            inc i, parseInt(s, n, i)
            yield n
        else:
            raise newException(ValueError,
                "expected a digit in data section but got '" & ch &
                "' ASCii code: " & $ch.ord)

func needsToComplete(n, base: int): int =
    let rem = n mod base
    if rem == 0: 0
    else: base - rem

func complement(n, base: int): int =
    n + needsToComplete(n, base)

iterator findBits(s: string, width, offset: int): tuple[index: int, val: bool] =
    let
        diff = needsToComplete(width, 8)
        widthComplete = complement(width, 8)

    var c = 0
    for i in offset..s.high:
        let ch = s[i]
        case ch
        of Whitespace: discard
        of '0', '1':
            yield (c, ch == '1')

            inc c:
                if c mod widthComplete == width-1: diff+1
                else: 1
        else:
            raise newException(ValueError,
                    "expected whitespace or 1/0 but got: " & ch)

func add(s: var seq[byte], index: int, b: bool) =
    let
        q = index div 8
        r = index mod 8

    if s.len <= q:
        s.setLen q+1
    if b:
        s[q].setBit 7-r

# ----- utility API

const commonPnmExt* = ".pnm"
func fileExt*(magic: PnmMagic): string =
    ## returns file extension according to the magic
    case magic
    of bitMap: "pbm"
    of grayMap: "pgm"
    of pixMap: "ppm"

func toCompressed*(m: PnmMagic): PnmMagic =
    case m
    of P1: P4
    of P2: P5
    of P3: P6
    else: m

func toUnCompressed*(m: PnmMagic): PnmMagic =
    case m
    of P4: P1
    of P5: P2
    of P6: P3
    else: m

func getBool*(pnm: Pnm, x, y: int): bool =
    ## only applicable when `pnm`.magic is P1 or P4
    assert pnm.magic in bitMap
    let
        d = x + y*(pnm.width.complement 8)
        q = d div 8
        r = d mod 8
    pnm.data[q].testBit(7-r)

func setBool*(pnm: var Pnm, x, y: int, b: bool) =
    ## only applicable when `pnm`.magic is P1 or P4
    assert pnm.magic in bitMap
    let
        d = x + y*(pnm.width.complement 8)
        q = d div 8
        r = d mod 8
    if b: pnm.data[q].setBit(7-r)
    else: pnm.data[q].clearBit(7-r)

iterator pairsBool*(pnm: Pnm): tuple[position: Position, value: bool] =
    ## only applicable when `pnm`.magic is P1 or P4
    for y in 0 ..< pnm.height:
        for x in 0 ..< pnm.width:
            yield ((x, y), pnm.getBool(x, y))

func getGrayScale*(pnm: Pnm, x, y: int): uint8 =
    ## only applicable when `pnm`.magic is P2 or P5
    assert pnm.magic in grayMap
    pnm.data[x + y*pnm.width]

func setGrayScale*(pnm: var Pnm, x, y: int, g: uint8): uint8 =
    ## only applicable when `pnm`.magic is P2 or P5
    assert pnm.magic in grayMap
    pnm.data[x+y*pnm.width] = g

func getColor*(pnm: Pnm, x, y: int): Color =
    ## only applicable when `pnm`.magic is P3 or P6
    assert pnm.magic in pixMap
    let
        i = 3*(x+y*pnm.width)
        colors = pnm.data[i .. i+2]
    (colors[0], colors[1], colors[2])

func setColor*(pnm: var Pnm, x, y: int, color: Color) =
    ## only applicable when `pnm`.magic is P3 or P6
    assert pnm.magic in pixMap
    let i = 3*(x+y*pnm.width)
    pnm.data[i+0] = color.r
    pnm.data[i+1] = color.g
    pnm.data[i+2] = color.b

# ----- main API

func parsePnmContent(s: string, offset: int, result: var Pnm) =
    case result.magic
    of P1:
        for i, b in findBits(s, result.width, offset):
            result.data.add i, b

    of P2, P3:
        for n in findInts(s, offset):
            case result.magic
            of P2, P3:
                result.data.add n.byte
            else: impossible
    of compressed:
        result.data = cast[seq[byte]](s[offset..s.high])

func parsePnm*(s: string, captureComments = false): Pnm =
    ## parses your `.pnm`, `.pbm`, `.pgm`, `.ppm` files
    var
        lastCh = '\n'
        i = 0
        state = ppsMagic

    while i != s.len:
        let ch = s[i]

        if (lastCh in Newlines) and (ch == '#'):
            let newi = s.find('\n', i+1)
            if captureComments:
                result.comments.add strip s[i+1 ..< newi]
            i = newi
        elif ch in Whitespace: inc i
        else:
            case state
            of ppsMagic:
                var word: string
                inc i, s.parseIdent(word, i)
                result.magic = parseEnum[PnmMagic](word.toUpperAscii)
                inc state

            of ppsWidth:
                inc i, s.parseInt(result.width, i)
                inc state

            of ppsHeight:
                inc i, s.parseInt(result.height, i)
                inc state

            of ppsMaxVal:
                if result.magic notin bitMap:
                    inc i, s.parseInt(result.maxValue, i)
                else:
                    result.maxValue = 1
                inc state

            of ppsContent:
                parsePnmContent s, i, result
                break

        lastch = ch

func `$`*(pnm: Pnm, dropWhiteSpaces = false, addComments = true): string =
    ## convert the `.pnm`, `.pbm`, `.pgm`, `.ppm` file to its string representation
    result.addMulti $pnm.magic, '\n'

    for c in pnm.comments:
        result.addMulti '#', ' ', $pnm.magic, '\n'

    result.addMulti $pnm.width, ' '
    result.addMulti $pnm.height, '\n'

    if pnm.magic notin bitMap:
        result.addMulti $pnm.maxValue, '\n'

    case pnm.magic
    of P1:
        for y in 0..<pnm.height:
            for x in 0..<pnm.width:
                result.add toDigit pnm.getBool(x, y)
                if not dropWhiteSpaces:
                    result.add ' '
            if not dropWhiteSpaces:
                result.add '\n'

    of P2:
        for y in 0..<pnm.height:
            for x in 0..<pnm.width:
                result.addMulti $pnm.getGrayScale(x, y), ' '
            result.add '\n'

    of P3:
        for y in 0..<pnm.height:
            for x in 0..<pnm.width:
                let c = pnm.getColor(x, y)
                result.addMulti $c.r, ' ', $c.g, ' ', $c.b, ' '
            result.add '\n'

    of compressed:
        for i in pnm.data:
            result.add i.char
