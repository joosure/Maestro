defmodule SymphonyElixir.Platform.PrivAssets do
  @moduledoc false

  @default_otp_app :symphony_elixir
  @cache_rootname "symphony-elixir-priv-assets"

  @spec app_priv_root!(Path.t(), keyword()) :: Path.t()
  def app_priv_root!(relative_dir, opts \\ []) when is_binary(relative_dir) and is_list(opts) do
    otp_app = Keyword.get(opts, :otp_app, @default_otp_app)
    relative_dir = validate_relative_dir!(relative_dir)

    otp_app
    |> priv_dir!()
    |> real_priv_dir!()
    |> Path.join(relative_dir)
    |> Path.expand()
  end

  defp priv_dir!(otp_app) when is_atom(otp_app) and not is_nil(otp_app) do
    case :code.priv_dir(otp_app) do
      path when is_list(path) ->
        to_string(path)

      {:error, reason} ->
        raise ArgumentError,
              "could not resolve priv directory for otp_app #{inspect(otp_app)}: #{inspect(reason)}"
    end
  end

  defp priv_dir!(otp_app) do
    raise ArgumentError, "application priv asset otp_app must be an atom, got #{inspect(otp_app)}"
  end

  defp real_priv_dir!(priv_dir) when is_binary(priv_dir) do
    if File.dir?(priv_dir) do
      priv_dir
    else
      extracted_priv_dir!(priv_dir)
    end
  end

  defp extracted_priv_dir!(expected_priv_dir) do
    script_path = escript_path!()
    cache_root = extraction_cache_root!(script_path)
    priv_dir = ensure_extracted_priv_dir!(script_path, cache_root, expected_priv_dir)
    add_extracted_code_paths(cache_root)

    if File.dir?(priv_dir) do
      priv_dir
    else
      raise ArgumentError,
            "could not resolve extracted application priv directory: #{inspect(priv_dir)}"
    end
  end

  defp add_extracted_code_paths(cache_root) do
    [cache_root, "*", "ebin"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.each(&:code.add_patha(String.to_charlist(&1)))
  end

  defp escript_path! do
    script_path =
      :escript.script_name()
      |> List.to_string()
      |> Path.expand()

    cond do
      script_path in ["", Path.expand("-e")] ->
        raise ArgumentError, "could not resolve escript path for application priv assets"

      File.regular?(script_path) ->
        script_path

      true ->
        raise ArgumentError,
              "could not resolve escript path for application priv assets: #{inspect(script_path)}"
    end
  end

  defp extraction_cache_root!(script_path) do
    case File.stat(script_path) do
      {:ok, %File.Stat{size: size, mtime: mtime}} ->
        cache_key = :erlang.phash2({script_path, size, mtime}) |> Integer.to_string(36)
        Path.join([System.tmp_dir!(), @cache_rootname, cache_key])

      {:error, reason} ->
        raise ArgumentError,
              "could not stat escript for application priv assets: #{inspect(script_path)} reason=#{inspect(reason)}"
    end
  end

  defp ensure_extracted_priv_dir!(script_path, cache_root, expected_priv_dir) do
    expected_priv_dir = Path.expand(expected_priv_dir)

    case find_extracted_priv_dir(cache_root, script_path, expected_priv_dir) do
      {:ok, priv_dir} ->
        priv_dir

      :error ->
        File.rm_rf!(cache_root)
        File.mkdir_p!(cache_root)

        script_path
        |> escript_archive!()
        |> unzip_archive!(cache_root)

        case find_extracted_priv_dir(cache_root, script_path, expected_priv_dir) do
          {:ok, priv_dir} ->
            priv_dir

          :error ->
            raise ArgumentError,
                  "could not find bundled application priv directory after extracting #{inspect(script_path)}"
        end
    end
  end

  defp find_extracted_priv_dir(cache_root, script_path, expected_priv_dir) do
    direct_candidate =
      expected_priv_dir
      |> Path.relative_to(script_path)
      |> direct_candidate(cache_root)

    cond do
      is_binary(direct_candidate) and File.dir?(direct_candidate) ->
        {:ok, direct_candidate}

      true ->
        [cache_root, "**", "priv"]
        |> Path.join()
        |> Path.wildcard()
        |> Enum.find(&File.dir?/1)
        |> case do
          nil -> :error
          priv_dir -> {:ok, priv_dir}
        end
    end
  end

  defp direct_candidate(relative_path, cache_root) do
    if Path.type(relative_path) == :relative do
      Path.join(cache_root, relative_path)
    end
  end

  defp escript_archive!(script_path) do
    case :escript.extract(String.to_charlist(script_path), []) do
      {:ok, sections} ->
        case Keyword.fetch(sections, :archive) do
          {:ok, archive_bin} when is_binary(archive_bin) ->
            archive_bin

          {:ok, _section} ->
            raise ArgumentError, "invalid escript archive for application priv assets"

          :error ->
            raise ArgumentError, "missing escript archive for application priv assets"
        end

      {:error, reason} ->
        raise ArgumentError, "could not extract escript archive for application priv assets: #{inspect(reason)}"
    end
  end

  defp unzip_archive!(archive_bin, cache_root) do
    case :zip.extract(archive_bin, [{:cwd, String.to_charlist(cache_root)}]) do
      {:ok, _paths} ->
        cache_root

      {:error, reason} ->
        raise ArgumentError, "could not unzip escript archive for application priv assets: #{inspect(reason)}"
    end
  end

  defp validate_relative_dir!(relative_dir) do
    relative_dir = String.trim(relative_dir)
    segments = Path.split(relative_dir)

    cond do
      relative_dir == "" ->
        raise ArgumentError, "application priv asset root must be non-empty"

      Path.type(relative_dir) == :absolute ->
        raise ArgumentError, "application priv asset root must be relative"

      contains_forbidden_relative_segment?(segments) ->
        raise ArgumentError, "application priv asset root must stay under the application priv directory"

      true ->
        Path.join(segments)
    end
  end

  defp contains_forbidden_relative_segment?(segments) do
    Enum.any?(segments, &(&1 in [".", ".."]))
  end
end
