defmodule TSONTest do
  use ExUnit.Case
  doctest TSON

  def hexs(s) when is_binary(s) do
    Regex.replace(~R{[^A-Fa-f0-9]}, s, "") |> Base.decode16!(case: :mixed)
  end

  def hexs(s) when is_list(s) do
    to_string(s) |> hexs
  end

  test "empty" do
    assert TSON.encode(nil) == <<7>>
    assert TSON.decode(<<7>>) == nil
  end

  test "true" do
    assert TSON.encode(true) == <<5>>
    assert TSON.decode(<<5>>) == true
  end

  test "false" do
    assert TSON.encode(false) == <<6>>
    assert TSON.decode(<<6>>) == false
  end

  test "int0" do
    original = 0
    encoding = TSON.encode(original)
    assert encoding == hexs('40')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "int27" do
    original = 27
    encoding = TSON.encode(original)
    assert encoding == hexs('5B')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "intNeg13" do
    original = -13
    encoding = TSON.encode(original)
    assert encoding == hexs('3B 0D')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "intNeg2000" do
    original = -2000
    encoding = TSON.encode(original)
    assert encoding == hexs('3B D00F')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "int63" do
    original = 63
    encoding = TSON.encode(original)
    assert encoding == hexs('7F')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "int64" do
    original = 64
    encoding = TSON.encode(original)
    assert encoding == hexs('3A 40')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "int123456" do
    original = 123_456
    encoding = TSON.encode(original)
    assert encoding == hexs('3A C0C407')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "string0" do
    original = %TSON.String{utf8: ""}
    assert TSON.encode(original) == hexs("0E 00")
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "string1" do
    original = %TSON.String{utf8: "1"}
    assert TSON.encode(original) == hexs("10 31")
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "string13" do
    original = %TSON.String{utf8: "\t13th Friday\n"}
    assert TSON.encode(original) == hexs('1C 0931337468204672696461790A')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "string24" do
    s24 = %TSON.String{utf8: String.duplicate("Z", 24)}

    assert TSON.encode(s24) == hexs('27 5A5A5A5A5A5A5A5A 5A5A5A5A5A5A5A5A 5A5A5A5A5A5A5A5A')

    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "string25" do
    s25 = %TSON.String{utf8: String.duplicate("y", 25)}

    assert TSON.encode(s25) == hexs('0E 7979797979797979 7979797979797979 7979797979797979 7900')

    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "binaryBytes" do
    original = <<11, 22, 33, 44, 55, 66, 77>>
    assert TSON.encode(original) == hexs('03 07 0B16212C37424D')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "array0" do
    original = []
    encoding = TSON.encode(original)
    assert encoding == hexs('02 00')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "array1" do
    original = [%TSON.String{utf8: "t"}]
    encoding = TSON.encode(original)
    assert encoding == hexs('2C 1074')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "array4" do
    original = [true, false, false, true]
    encoding = TSON.encode(original)
    assert encoding == hexs('2F 05 06 06 05')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "array5" do
    original = [0, 2, 0, 63, 200]
    encoding = TSON.encode(original)
    assert encoding == hexs('02 40 42 40 7F 3A C8 01 00')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "LatLon" do
    coord = %TSON.LatLon{latitude: 46.083529, longitude: -118.283026}
    encoding = TSON.encode(coord)
    assert encoding == hexs('09 A8 D4 E4 89 FA C5 58')
    # decoded = TSON.decode(encoding)
    # self.assertIsNotNone(decoded)
    # self.assertIsInstance(decoded, TSON.LatLon)
    # self.assertTrue((coord.latitude - decoded.latitude) < 0.00001)
    # self.assertTrue((coord.longitude - decoded.longitude) < 0.00001)
  end

  test "timestamp" do
    {:ok, original, _} = DateTime.from_iso8601("2016-09-19T07:00:00Z")
    encoding = TSON.encode(original)
    assert encoding == hexs('0480DB8AB654')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "negativeTimestamp" do
    {:ok, original, _} = DateTime.from_iso8601("1970-09-19T07:00:00Z")
    encoding = TSON.encode(original)
    assert encoding == hexs('088095FEC6CB29')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "duration500" do
    duration = %TSON.Duration{amount: 500, unit: :minute}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 02 F403')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration500MinNeg" do
    duration = %TSON.Duration{amount: -500, unit: :minute}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 82 F403')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration30Seconds" do
    duration = %TSON.Duration{amount: 30, unit: :second}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 01 1E')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration60SecondsNeg" do
    duration = %TSON.Duration{amount: -60, unit: :second}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 82 01')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration61SecondsNeg" do
    duration = %TSON.Duration{amount: -61, unit: :second}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 81 3D')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration8000Milliseconds" do
    duration = %TSON.Duration{amount: 8000, unit: :millisecond}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 01 08')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration8001Milliseconds" do
    duration = %TSON.Duration{amount: 8001, unit: :millisecond}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 03 C13E')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration7777MillisecondsNeg" do
    duration = %TSON.Duration{amount: -7777, unit: :millisecond}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 83 E13C')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration15Microseconds" do
    duration = %TSON.Duration{amount: 15, unit: :microsecond}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 06 0F')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration1MicrosecondsNeg" do
    duration = %TSON.Duration{amount: -1, unit: :microsecond}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 86 01')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration24Hours" do
    duration = %TSON.Duration{amount: 24, unit: :hour}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 04 18')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "duration180HoursNeg" do
    duration = %TSON.Duration{amount: -180, unit: :hour}
    encoding = TSON.encode(duration)
    assert encoding == hexs('37 84 B401')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, duration)
  end

  test "float200_0" do
    original = 200.0
    encoding = TSON.encode(original)
    assert encoding == hexs('3AC801')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "floatNeg6789_0" do
    original = -6789.0
    encoding = TSON.encode(original)
    assert encoding == hexs('3B8535')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "float0_25" do
    original = 0.25
    encoding = TSON.encode(original)
    assert encoding == hexs('3C0000803E')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "float0_3333" do
    original = 0.3333
    encoding = TSON.encode(original)
    assert encoding == hexs('3D696FF085C954D53F')
    # decoded = TSON.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "repeatedStrings" do
    original =
      ["hello", "kitty", "hello", "world", "here", "kitty", "kitty", "kitty"]
      |> Enum.map(fn x -> %TSON.String{utf8: x} end)

    encoding = TSON.encode(original)
    expected = hexs('02 1468656C6C6F 146B69747479 0F00 14776F726C64 1368657265 0F01 0F01 0F01 00')
    assert encoding == expected
    # decoded = tson.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "nested repeated strings" do
    a =
      ["hello", "kitty", "hello", "world"]
      |> Enum.map(fn x -> %TSON.String{utf8: x} end)

    b =
      ["here", "kitty", "kitty", "kitty"]
      |> Enum.map(fn x -> %TSON.String{utf8: x} end)

    original = [a, b]
    encoding = TSON.encode(original)

    expected =
      hexs('2D 2F 1468656C6C6F 146B69747479 0F00 14776F726C64 2F 1368657265 0F01 0F01 0F01')

    assert encoding == expected
    # decoded = tson.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "Doc0" do
    original = %{}
    encoding = TSON.encode(original)
    assert encoding == hexs('01 00')
    # decoded = tson.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "Doc1" do
    original = %{"1": nil}
    encoding = TSON.encode(original)
    assert encoding == hexs('28073100')
    # decoded = tson.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "Doc4" do
    original = %{"1" => nil, "2" => nil, "3" => nil, "4" => nil}
    encoding = TSON.encode(original)
    assert encoding == hexs('2B 073100 073200 073300 073400')
    # decoded = tson.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "Doc5" do
    original = %{"1" => nil, "2" => nil, "3" => nil, "4" => nil, "5" => nil}
    encoding = TSON.encode(original)
    assert encoding == hexs('01 073100 073200 073300 073400 073500 00')
    # decoded = tson.decode(encoding)
    # self.assertEqual(decoded, original)
  end

  test "RepeatedField" do
    doc1 = %{"1" => 41}
    doc2 = %{"2" => %TSON.String{utf8: "3"}}
    doc3 = %{"1" => <<>>}
    doc4 = %{"2" => false}
    container = %{"1" => doc1, "2" => doc2, "3" => doc3, "4" => doc4}
    encoding = TSON.encode(container)
    expected = hexs('2B   A8 693100 00   A8 10333200 01  28 830000 3300   28 8601 3400')
    assert encoding == expected
    # let decoded = TSON.decode(data: encoded)
    # XCTAssertEqual(decoded, tson)
  end

  test "family nested" do
    # Mark
    #    dad: Larry
    #    mom: Lorraine
    # Travis
    #    dad: Gary
    #    mom: Suzanne
    # inner 1
    # Larry/dad
    # Lorrain/mom
    # inner end
    # Mark
    # inner 2
    # Gary/dad
    # Suzanne/mom
    # inner end
    # Travis
    # outer end
    source =
      '29' ++
        '29' ++
        '14 4C61727279 646164 00' ++
        '17 4C6F727261696E65 6D6F6D 00' ++
        '4D61726B 00' ++
        '29' ++
        '93 47617279 00' ++
        '96 53757A616E6E65 01' ++
        '547261766973 00'

    complicated = %{
      "Mark" => %{"dad" => %TSON.String{utf8: "Larry"}, "mom" => %TSON.String{utf8: "Lorraine"}},
      "Travis" => %{"dad" => %TSON.String{utf8: "Gary"}, "mom" => %TSON.String{utf8: "Suzanne"}}
    }

    encoding = TSON.encode(complicated)
    assert encoding == hexs(source)
    # XCTAssertEqual(doc["Mark"]["dad"].string, "Larry")
    # XCTAssertEqual(doc["Mark"]["mom"].string, "Lorraine")
    # XCTAssertEqual(doc["Travis"]["dad"].string, "Gary")
    # XCTAssertEqual(doc["Travis"]["mom"].string, "Suzanne")
  end
end
