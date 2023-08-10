# pattern according to https://oceancolor.gsfc.nasa.gov/staff/norman/seawifs_image_cookbook/faux_shuttle/Pan.html
# magic :: P1/P4
# whitespace/comment
# width
# whitespace/comment
# height
# whitespace/comment
# content :: 0 1

import std/[strutils, parseutils, bitops, math, macros]

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

# ----- utils

func toDigit(b: bool): char =
    case b
    of true: '1'
    of false: '0'

func toDigit(b: byte): char =
    case b
    of 1.byte: '1'
    of 0.byte: '0'
    else:
        raise newException(ValueError, "invalid byte value: " & $b.int)

func addByte(arr: var seq[byte], b: byte, cutAfter: range[0..7]) =
    for i in countdown(7, cutAfter):
        arr.add testbit(b, i).byte

macro addMulti(wrapper: untyped, elems: varargs[untyped]): untyped =
    result = newStmtList()
    for e in elems:
        result.add quote do:
            `wrapper`.add `e`

func checkInRange(pan: Pan, x, y: int): bool =
    x in 0 ..< pan.width and
    y in 0 ..< pan.height

# ----- API

func size*(pan: Pan): int =
    pan.width * pan.height

func fileExt*(magic: PanMagic): string = 
    case magic
    of bitMap: "pbm"
    of grayMap: "pgm"
    of pixMap: "ppm"

func parsePanContent*(s: string, offset: int, result: var Pan) =
    let
        size = s.len - offset
        extraBits = result.width mod 8
        bytesRow = result.width.ceilDiv 8

        limit =
            if extraBits == 0: 0
            else: 8-extraBits

    for i in 0 ..< size:
        let ch = s[i + offset]
        case result.magic
        of P1:
            case ch
            of Whitespace: discard
            of '1': result.data.add 1.byte
            of '0': result.data.add 0.byte
            else: raise newException(ValueError,
                    "expected 1 or 0 in data section but got '" & ch &
                    "' ASCii code: " & $ch.ord)

        of P4:
            let
                cut =
                    if i mod bytesRow == bytesRow-1: limit
                    else: 0

            result.data.addByte cast[byte](ch), cut

        else:
            raise newException(ValueError, "not implemented")

func getBool*(p: Pan, x, y: int): bool =
    assert p.checkInRange(x, y)
    case p.magic
    of P1:
        p.data[x + y*p.width] == 1.byte
    of P4:
        let
            d = x + y*p.width
            q = d div 8
            r = d mod 8
        p.data[q].testBit(r)
    else:
        raise newException(ValueError, "?")

# func getGrayScale*(pan: Pan, x, y: int): uint8 =
#     assert pan.magic in grayMap
#     assert pan.checkInRange(x, y)
#     pan.g2[pan.getIndex(x, y)]

# func setGrayScale*(pan: var Pan, x, y: int, b: uint8): uint8 =
#     assert pan.magic in grayMap
#     assert pan.checkInRange(x, y)
#     pan.g2[pan.getIndex(x, y)] = b

# func getColor*(pan: Pan, x, y: int): ColorRgb =
#     assert pan.magic in pixMap
#     assert pan.checkInRange(x, y)
#     pan.p2[pan.getIndex(x, y)]

# func setColor*(pan: var Pan, x, y: int, b: ColorRgb) =
#     assert pan.magic in pixMap
#     assert pan.checkInRange(x, y)
#     pan.p2[pan.getIndex(x, y)] = b

iterator pairsBool*(pan: Pan): tuple[position: Position, value: bool] =
    for y in 0..<pan.height:
        for x in 0..<pan.width:
            yield ((x, y), pan.getBool(x, y))

func parsePan*(s: string, captureComments = false): Pan =
    var
        lastCh = '\n'
        i = 0.Natural
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

func `$`*(pan: Pan, addComments = true): string =
    result.addMulti $pan.magic, '\n'

    for c in pan.comments:
        result.addMulti '#', ' ', $pan.magic, '\n'

    result.addMulti $pan.width, ' '
    result.addMulti $pan.height, '\n'

    case pan.magic
    of P1:
        for i in 0..<pan.size:
            let whitespace =
                if i+1 == pan.width: '\n'
                else: ' '

            result.addMulti toDigit pan.data[i], whitespace

    else:
        raise newException(ValueError, "not implemented")
