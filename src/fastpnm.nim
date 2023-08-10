import std/[strutils, parseutils, bitops, macros]

type
    PanParserState = enum
        ppsMagic
        ppsWidth
        ppsHeight
        ppsMaxVal
        ppsContent

    PanMagic* = enum
        bitMapRaw = "P1"
        grayMapRaw = "P2"
        pixMapRaw = "P3"
        bitMapBinray = "P4"
        grayMapBinray = "P5"
        pixMapBinray = "P6"

    Pan* = object
        magic*: PanMagic
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

func inBoard(pan: Pan, x, y: int): bool =
    x in 0 ..< pan.width and
    y in 0 ..< pan.height

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

func size*(pan: Pan): int =
    pan.width * pan.height

func fileExt*(magic: PanMagic): string =
    case magic
    of bitMap: "pbm"
    of grayMap: "pgm"
    of pixMap: "ppm"

func getBool*(p: Pan, x, y: int): bool =
    assert p.inBoard(x, y)
    case p.magic
    of bitMap:
        let
            d = x + y*(p.width.complement 8)
            q = d div 8
            r = d mod 8
        p.data[q].testBit(7-r)
    else:
        raise newException(ValueError, "the magic '" & $p.magic & "' does not have bool value")

iterator pairsBool*(pan: Pan): tuple[position: Position, value: bool] =
    for y in 0 ..< pan.height:
        for x in 0 ..< pan.width:
            yield ((x, y), pan.getBool(x, y))

func getGrayScale*(pan: Pan, x, y: int): uint8 =
    assert pan.magic in grayMap
    pan.data[x + y*pan.width]

func setGrayScale*(pan: var Pan, x, y: int, g: uint8): uint8 =
    assert pan.magic in grayMap
    pan.data[x+y*pan.width] = g

func getColor*(pan: Pan, x, y: int): Color =
    assert pan.magic in pixMap
    let
        i = 3*(x+y*pan.width)
        colors = pan.data[i .. i+2]
    (colors[0], colors[1], colors[2])

func setColor*(pan: var Pan, x, y: int, color: Color) =
    assert pan.magic in pixMap
    let i = 3*(x+y*pan.width)
    pan.data[i+0] = color.r
    pan.data[i+1] = color.g
    pan.data[i+2] = color.b

# ----- main API

func parsePanContent(s: string, offset: int, result: var Pan) =
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

func parsePan*(s: string, captureComments = false): Pan =
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
                result.magic = parseEnum[PanMagic](word.toUpperAscii)
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
                inc state

            of ppsContent:
                parsePanContent s, i, result
                break

        lastch = ch

func `$`*(pan: Pan, dropWhiteSpaces = false, addComments = true): string =
    result.addMulti $pan.magic, '\n'

    for c in pan.comments:
        result.addMulti '#', ' ', $pan.magic, '\n'

    result.addMulti $pan.width, ' '
    result.addMulti $pan.height, '\n'

    if pan.magic notin bitMap:
        result.addMulti $pan.maxValue, '\n'

    case pan.magic
    of P1:
        for y in 0..<pan.height:
            for x in 0..<pan.width:
                result.add toDigit pan.getBool(x, y)
                if not dropWhiteSpaces:
                    result.add ' '
            if not dropWhiteSpaces:
                result.add '\n'

    of P2:
        for y in 0..<pan.height:
            for x in 0..<pan.width:
                result.addMulti $pan.getGrayScale(x, y), ' '
            result.add '\n'

    of P3:
        for y in 0..<pan.height:
            for x in 0..<pan.width:
                let c = pan.getColor(x, y)
                result.addMulti $c.r, ' ', $c.g, ' ', $c.b, ' '
            result.add '\n'

    of compressed:
        for i in pan.data:
            result.add i.char
