defmodule Tar do
  @author "Gregoire Lejeune <gregoire.lejeune@free.fr>"
  @moduledoc """
  Manipulate tar archive

  ## How to use this

  Create a tar archive :

      tar = Tar.Archive[ file: "/path/to/archive.tar" ]
      tar = tar 
            |> Tar.add("path/to/file.1", "path/to")
            |> Tar.add("root/to/file.2", "root")
            |> Tar.create()

  Extract content of a tar archive

      tar = Tar.Archive[ file: "/path/to/archive.tar" ]
      Tar.extract(tar)

  or

      Tar.Archive[ file: "/path/to/archive.tar" ] |> Tar.extract

  Get informations about the content of a tar archive

      tar = Tar.Archive[ file: "/path/to/archive.tar" ] |> Tar.read
      number_of_file_in_tar = Tar.count(tar)
      file_info = Tar.get(tar, file_id)

  """

  defexception FileError, message: "unknown error", can_retry: false do
    def full_message(me) do
      "Tar failed: #{me.message}, retriable: #{me.can_retry}"
    end
  end

  defexception HeaderError, message: "wrong header format", can_retry: false do
    def full_message(me) do
      "Tar failed: #{me.message}, retriable: #{me.can_retry}"
    end
  end

  @header_size          512

  @header_name_pos        0
  @header_name_size     100
  @header_mode_pos      100
  @header_mode_size       8
  @header_uid_pos       108
  @header_uid_size        8
  @header_gid_pos       116
  @header_gid_size        8
  @header_size_pos      124
  @header_size_size      12
  @header_mtime_pos     136
  @header_mtime_size     12
  @header_chksum_pos    148
  @header_chksum_size     8
  @header_type_pos      156
  @header_type_size       1
  @header_linkname_pos  157
  @header_linkname_size 100
  @header_magic_pos     257
  @header_magic_size      6
  @header_version_pos   263
  @header_version_size    2
  @header_uname_pos     265
  @header_uname_size     32
  @header_gname_pos     297
  @header_gname_size     32
  @header_devmajor_pos  329
  @header_devmajor_size   8
  @header_devminor_pos  337
  @header_devminor_size   8
  @header_prefix_pos    345
  @header_prefix_size   155

  @tar_normal_file       "0"
  @tar_hard_link         "1"
  @tar_symbolic_link     "2"
  @tar_character_special "3"
  @tar_block_special     "4"
  @tar_directory         "5"
  @tar_fifo              "6"
  @tar_continuous_file   "7"
  @tar_pax_extension     "x"
  @tar_gpax_extension    "g"

  @tar_record_size 512
  @io_buffer_size  2048*@tar_record_size

  defrecord Header, 
    name: nil, 
    mode: nil,
    uid: nil,
    gid: nil,
    size: nil,
    mtime: nil,
    chksum: nil,
    type: nil,
    linkname: nil,
    magic: nil,
    version: nil,
    uname: nil,
    gname: nil,
    devmajor: nil,
    devminor: nil,
    prefix: nil

  defrecord Pax, header: nil, data: nil do
    record_type header: Header.t
    record_type data: String.t
  end

  defrecord Entry, pax: nil, has_pax: nil, header: nil, content: nil, archive_path: nil, system_path: nil do
    record_type pax: Pax.t
    record_type has_pax: boolean
    record_type header: Header.t
    record_type content: any
    record_type archive_path: String.t
    record_type system_path: String.t
  end

  defrecord EntryInfo, path: nil, size: nil, type: nil, uname: nil, gname: nil do
    @moduledoc """
    Tar entry informations
    """
    record_type path: String.t
    record_type size: number
    record_type type: String.t
    record_type uname: String.t
    record_type gname: String.t
  end
  
  defrecord Archive, path: nil, entries: [] do
    @moduledoc """
    Tar archive
    """
    record_type path: String.t
    record_type entries: [ Entry.t ]
  end

  defp octstring_to_int(x) do
    Enum.reduce(bitstring_to_list(x), 0, fn(e, acc) -> 
      if e >= 48 and e <= 55 do
        (acc * 8) + (e - 48) 
      else
        acc
      end
    end)
  end

  defp get_checksum(header_data) do
    result = Enum.reduce(bitstring_to_list(header_data), [0, 0], fn(x, acc) -> 
      if Enum.at(acc, 1) < @header_chksum_pos or Enum.at(acc, 1) >= @header_chksum_pos + @header_chksum_size do
        [Enum.at(acc, 0) + x, Enum.at(acc, 1) + 1]
      else
        [Enum.at(acc, 0) + 0x20, Enum.at(acc, 1) + 1] 
      end
    end)
    Enum.at(result, 0)
  end

  defp parse_header(data) do
    Tar.Header[
      name: String.slice(data, @header_name_pos, @header_name_size),
      mode: String.slice(data, @header_mode_pos, @header_mode_size),
      uid: String.slice(data, @header_uid_pos, @header_uid_size),
      gid: String.slice(data, @header_gid_pos, @header_gid_size),
      size: String.slice(data, @header_size_pos, @header_size_size),
      mtime: String.slice(data, @header_mtime_pos, @header_mtime_size),
      chksum: String.slice(data, @header_chksum_pos, @header_chksum_size),
      type: String.slice(data, @header_type_pos, @header_type_size),
      linkname: String.slice(data, @header_linkname_pos, @header_linkname_size),
      magic: String.slice(data, @header_magic_pos, @header_magic_size),
      version: String.slice(data, @header_version_pos, @header_version_size),
      uname: String.slice(data, @header_uname_pos, @header_uname_size),
      gname: String.slice(data, @header_gname_pos, @header_gname_size),
      devmajor: String.slice(data, @header_devmajor_pos, @header_devmajor_size),
      devminor: String.slice(data, @header_devminor_pos, @header_devminor_size),
      prefix: String.slice(data, @header_prefix_pos, @header_prefix_size)
    ]
  end

  defp verify_checksum(data, chksum) do
    get_checksum(data) == octstring_to_int(chksum)
  end

  @doc """
  Extract all content of a Tar archive
  """
  @spec extract(Archive.t, String.t) :: Archive.t
  def extract(archive, path) do
    {status, io} = File.open(archive.path, [:read])
    if :error == status do
      raise Tar.FileError, message: io
    end

    extract_entry(io, path)

    archive
  end
  def extract(archive) do
    extract(archive, ".")
  end

  defp extract_entry(io, path) do
    data = IO.read(io, @header_size)
    case data do
      {:error, reason} -> raise Tar.FileError, message: data
      :eof -> nil
      _ -> ( 
        if String.length(String.strip(data, 0)) > 0 do
          perform_extract_entry(io, path, data)
        else
          extract_entry(io, path)
        end
      )
    end
  end

  defp perform_extract_entry(io, path, data) do
    header = parse_header(data)
    unless verify_checksum(data, header.chksum) do
      raise Tar.HeaderError, message: "Invalid checksum"
    end

    case header.type do
      @tar_normal_file -> (
        file_size = octstring_to_int(header.size)
        output_path = path
        if String.length(String.strip(header.prefix, 0)) > 0 do
          output_path = Path.join(output_path, String.strip(header.prefix, 0))
        end
        output_path = Path.absname(Path.join(output_path, String.strip(header.name, 0)))
        output_parent_path = Path.dirname(output_path)
        unless File.exists?(output_parent_path) do
          File.mkdir_p!(output_parent_path)
        end

        extract_file(io, output_path, file_size)
      )
      @tar_directory -> (
        output_path = path
        if String.length(String.strip(header.prefix, 0)) > 0 do
          output_path = Path.join(output_path, String.strip(header.prefix, 0))
        end
        output_path = Path.absname(Path.join(output_path, String.strip(header.name, 0)))

        unless File.exists?(output_path) do
          File.mkdir_p!(output_path)
        end
      )
      @tar_pax_extension -> ( 
        pax = read_pax_data(io, octstring_to_int(header.size))
        output_path = path

        data = IO.read(io, @header_size)
        case data do
          {:error, reason} -> raise Tar.FileError, message: data
          :eof -> raise Tar.FileError, message: "Unexpected end of file"
          _ -> ( 
            if String.length(String.strip(data, 0)) <= 0 do
              raise Tar.FileError, message: "Unexpected empty header"
            end
          )
        end

        header = parse_header(data)
        unless verify_checksum(data, header.chksum) do
          raise Tar.HeaderError, message: "Invalid checksum"
        end

        if nil == pax["path"] or 0 < size(pax["path"]) do
          output_path = Path.absname(Path.join(output_path, pax["path"]))
        else
          if String.length(String.strip(header.prefix, 0)) > 0 do
            output_path = Path.join(output_path, String.strip(header.prefix, 0))
          end
          output_path = Path.absname(Path.join(output_path, String.strip(header.name, 0)))
        end

        output_parent_path = Path.dirname(output_path)
        unless File.exists?(output_parent_path) do
          File.mkdir_p!(output_parent_path)
        end

        case header.type do
          @tar_normal_file -> (
            file_size = octstring_to_int(header.size)
            extract_file(io, output_path, file_size)
          )
          _ -> nil # TODO: This can't be so simple !
        end
      )
      @tar_gpax_extension -> ( 
        # TODO but not now !
        IO.warn "Global PAX not yet supported!"
      )
      @tar_fifo              -> IO.warn "Ignore fifo in tar file"
      @tar_continuous_file   -> IO.warn "Ignore continuous file in tar file"
      @tar_hard_link         -> IO.warn "Ignore hard link in tar file"
      @tar_symbolic_link     -> IO.warn "Ignore symbolic link in tar file"
      @tar_character_special -> IO.warn "Ignore character special in tar file"
      @tar_block_special     -> IO.warn "Ignore block special in tar file"
      _                      -> IO.warn "Ignore undefined in tar file"
    end

    extract_entry(io, path)
  end

  defp read_pax_data(io, size) do
    data = read_pax_data(io, size, "")
    List.foldl String.split(data, %r/\n/), HashDict.new, fn (line, acc) ->
      unless line == "" do
        cut_pos = Enum.find_index(String.graphemes(line), fn(x) -> x == " " end)
        if nil == cut_pos do
          raise Tar.FileError, message: "Malformated PAX data"
        end

        {len, _} = String.to_integer(String.slice(line, 0, cut_pos))
        line_data = String.slice(line, cut_pos+1, size(line))
        if len != size(line)+1 do
          raise Tar.FileError, message: "Malformated PAX data"
        end

        [key, value] = String.split(line_data, %r/=/, global: false)
        Dict.put(acc, key, value)
      else
        acc
      end
    end
  end

  defp read_pax_data(io, size, data) do
    read_size = @tar_record_size
    if size < @tar_record_size do
      read_size = size
    end

    new_data = IO.read(io, read_size)
    case new_data do
      {:error, reason} -> raise Tar.FileError, message: reason
      _ -> data = data <> new_data
    end

    if read_size < @tar_record_size do
      case IO.read(io, @tar_record_size - read_size) do
        {:error, reason} -> raise Tar.FileError, message: reason
        _ -> nil
      end
    end

    if size - @tar_record_size > 0 do
      data = read_pax_data(io, size - @tar_record_size, data)
    end

    data
  end

  defp nearest_upper_block_multiple(bytes) do
    if 0 == rem(bytes, @tar_record_size) do
      bytes
    else
      @tar_record_size * (div(bytes, @tar_record_size) + 1)
    end
  end

  defp extract_data(io, oio, size) do
    write_data = Enum.min([size, @io_buffer_size])
    read_bytes = nearest_upper_block_multiple(write_data)

    data = IO.binread(io, read_bytes)
    case data do
      {:error, reason} -> raise Tar.FileError, message: data
      _ -> nil
    end

    case IO.binwrite(oio, :binary.part(data, {0, write_data})) do
      {:error, reason} -> raise Tar.FileError, message: data
      _ -> nil
    end

    size = size - read_bytes

    if size > 0 do
      extract_data(io, oio, size)
    end
  end

  defp extract_file(io, filename, size) do
    {status, oio} = File.open(filename, [:write])
    if :error == status do
      raise Tar.FileError, message: io
    end

    extract_data(io, oio, size)

    case File.close(oio) do
      {:error, reason} -> raise Tar.FileError, message: reason
      _ -> nil
    end
  end

  @doc """
  Read the content of a Tar archive
  """
  @spec read(Archive.t) :: Archive.t
  def read(archive) do
    # TODO
    archive
  end

  @doc """
  Get the number of file in the tar archive
  """
  @spec count(Archive.t) :: number
  def count(archive) do
    # TODO
    0
  end

  @doc """
  Get tar entry informations
  """
  @spec get(Archive.t, number) :: EntryInfo.t
  def get(archive, id) do
    # TODO
    nil
  end

  @doc """
  Create a Tar file
  """
  @spec create(Archive.t) :: Archive.t
  def create(archive) do
    # TODO
    archive
  end

  @doc """
  Add a file to an archive
  """
  @spec add(Archive.t, String.t, String.t) :: Archive.t
  def add(archive, file, root) do
    # TODO
    archive
  end
  def add(archive, file) do 
    add(archive, file, "")
  end
end
