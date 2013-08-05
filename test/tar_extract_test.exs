Code.require_file "test_helper.exs", __DIR__

defmodule TarExtractTest do
  use ExUnit.Case

  test "extract one" do
    file = Path.expand('../samples/sample1.tar', __FILE__)
    output = Path.expand('../samples', __FILE__)

    tar = Tar.Archive[path: file]
    Tar.extract(tar, output)

    assert(File.exists?(Path.join(output, "file.txt")))
    File.rm!(Path.join(output, "file.txt"))
  end

  test "extract one (again)" do
    file = Path.expand('../samples/sample1.tar', __FILE__)
    output = Path.expand('../samples', __FILE__)

    Tar.Archive[path: file] |> Tar.extract(output)

    assert(File.exists?(Path.join(output, "file.txt")))
    File.rm!(Path.join(output, "file.txt"))
  end

  test "extract two" do
    file = Path.expand('../samples/sample2.tar', __FILE__)
    output = Path.expand('../samples', __FILE__)

    Tar.Archive[path: file] |> Tar.extract(output)

    assert(File.exists?(Path.join(output, "file1.txt")))
    assert(File.exists?(Path.join(output, "file2.txt")))
    File.rm!(Path.join(output, "file1.txt"))
    File.rm!(Path.join(output, "file2.txt"))
  end

  test "extract with dir" do
    file = Path.expand('../samples/sample3.tar', __FILE__)
    output = Path.expand('../samples', __FILE__)

    Tar.Archive[path: file] |> Tar.extract(output)

    assert(File.exists?(Path.join(output, "file0.txt")))
    assert(File.exists?(Path.join([output, "dir1", "file1.txt"])))
    assert(File.exists?(Path.join([output, "dir2", "file2.txt"])))
    File.rm!(Path.join(output, "file0.txt"))
    File.rm_rf!(Path.join(output, "dir1"))
    File.rm_rf!(Path.join(output, "dir2"))
  end

  test "extract with pax" do
    file = Path.expand('../samples/sample4.tar', __FILE__)
    output = Path.expand('../samples', __FILE__)

    Tar.Archive[path: file] |> Tar.extract(output)

    assert(File.exists?(Path.join([output, "pipo", "thisisaveryverylongfilenametoseeusepaxheaderinsteedofustarheaderintarfilewithfuckinglongjavaclass.txt"])))
    File.rm_rf!(Path.join(output, "pipo"))
  end
end
