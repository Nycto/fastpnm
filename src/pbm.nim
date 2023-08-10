# pattern according to https://oceancolor.gsfc.nasa.gov/staff/norman/seawifs_image_cookbook/faux_shuttle/Pan.html
# magic :: P1/P4
# whitespace/comment
# width
# whitespace/comment
# height
# whitespace/comment
# content :: 0 1

import std/[strutils, parseutils, bitops]
import bitty, chroma

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

    Matrix*[T] = distinct seq[T]

    Pan* = object
        width*, height*, maxValue*: Natural
        comments*: seq[string]

        case magic*: PanMagic
        of bitMapRaw, bitMapBinray:
            b2*: BitArray
        of grayMapRaw, grayMapBinray:
            g2*: Matrix[uint8]
        of pixMapRaw, pixMapBinray:
            p2*: Matrix[ColorRGB]

    Position* = tuple
        x, y: int

const
    P1* = bitMapRaw
    P2* = grayMapRaw
    P3* = pixMapRaw
    P4* = bitMapBinray
    P5* = grayMapBinray
    P6* = pixMapBinray

# ----- utils

template addMulti(z, a, b): untyped =
    z.add a
    z.add b

template addMulti(z, a, b, c): untyped =
    z.add a
    z.add b
    z.add c

func toDigit(b: bool): char =
    case b
    of true: '1'
    of false: '0'

func addByte(arr: var BitArray, b: byte, cutAfter: range[0..7]) =
    for i in countdown(7, cutAfter):
        arr.add testbit(b, i)

func ceilDiv(n, d: int): int =
    let t = n div d
    if n mod d == 0: t
    else: t + 1

func checkInRange(pan: Pan, x, y: int): bool =
    x in 0 ..< pan.width and
    y in 0 ..< pan.height

func getIndex(pan: Pan, x, y: int): int =
    y*pan.width + x

func code*(pm: PanMagic): range[1..6] = pm.ord + 1

# ----- API

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
        case result.magic.code
        of 1:
            case ch
            of Whitespace: discard
            of '1': result.b2.add true
            of '0': result.b2.add false
            else: raise newException(ValueError,
                    "expected 1 or 0 in data section but got '" & ch & '\'')

        of 4:
            let
                cut =
                    if i mod bytesRow == bytesRow-1: limit
                    else: 0

            result.b2.addByte cast[byte](ch), cut
        
        else:
            raise newException(ValueError, "not implemented")

func getBool*(pan: Pan, x, y: int): bool =
    assert pan.checkInRange(x, y)
    pan.b2[pan.getIndex(x, y)]

func setBool*(pan: Pan, x, y: int, b: bool): bool =
    assert pan.magic.code in [1, 4]
    assert pan.checkInRange(x, y)
    pan.b2[pan.getIndex(x, y)] = b

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
                result.comments.add s[i+1 ..< newi]
            i = newi
        elif ch in Whitespace: inc i
        else:
            case state
            of ppsMagic:
                var word: string
                inc i, s.parseIdent(word, i)
                case word.toUpperAscii
                of "P1": result.magic = bitMapRaw
                of "P4": result.magic = bitMapBinray
                else: raise newException(ValueError, "invalid magic: '" & ch & '\'')
                inc state

            of ppsWidth:
                inc i, s.parseInt(result.width, i)
                inc state

            of ppsHeight:
                inc i, s.parseInt(result.height, i)
                inc state

            of ppsMaxVal:
                # if resize.magic in [P1, P2]:
                inc state

            of ppsContent:
                result.b2 = newBitArray()
                parsePanContent s, i, result
                break

        lastch = ch

func `$`*(pan: Pan, addComments = true): string =
    result.addMulti $pan.magic, '\n'

    for c in pan.comments:
        result.addMulti '#', $pan.magic, '\n'

    result.addMulti $pan.width, ' '
    result.addMulti $pan.height, '\n'

    case pan.magic.code
    of 1:
        for i, b in pan.b2:
            let whitespace =
                if i+1   == pan.width: '\n'
                else: ' '

            result.addMulti toDigit(b), whitespace

    else:
        raise newException(ValueError, "not implemented")
