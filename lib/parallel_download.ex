defmodule ParallelDownload do
  @moduledoc """
  Parallel Downloader allows you to download files in chunks and in parallel way.
  Uses `:httpc` inside.
  """

  require Logger

  alias ParallelDownload.HTTPUtils
  alias ParallelDownload.FileUtils
  alias ParallelDownload.HTTPClient

  @doc """
  Downloads and saves file from given url to the given path.
  Pass chunk's size in bytes.
  Pass directory where downloaded file will be saved.
  Pass file name for downloading file.
  If this parameter is not set then app tries to extract filename form url and use it.
  If this not works it uses randomly generated file name.

  Also there are next availabale options:
    * `:request_timeout` - Time-out time for the request. The clock starts ticking when the request is sent. Time is in milliseconds. Default is 20 minutes.
    * `:connect_timeout` - Connection time-out time, used during the initial request, when the client is connecting to the server. Default is 20 minutes.
    * `:download_unsupported` - if true, downloads file as usual if server returns `Acceprt-ranges: none`. Default is false and it returns `:not_supported` error.

  Returns `{:ok, filepath}` where filepath is path to downloaded file.

  Returns `{:error, atom}` or `{:error, atom, reason}` in error cases.
  Errors might be:
    * `:url_not_valid` - given url is not valid.
    * `:enoent` - given directory is not exists.
    * `:no_access` - app doesn't have write access to given directory.
    * `:not_directory` - given directory is not directory.
    * `:server_error` - server returned any error status.
    * `:not_supported` - server doesn't accept range access to content.

  """
  def download_file(url, chunk_size_bytes, dir_to_download)
      when is_binary(url) and is_integer(chunk_size_bytes) and is_binary(dir_to_download) do
    download_file(
      url,
      chunk_size_bytes,
      dir_to_download,
      validate_filename("", url),
      default_opts()
    )
  end

  @spec download_file(binary(), non_neg_integer(), binary(), binary(), keyword()) ::
          {:error, atom()} | {:error, atom(), term()} | {:ok, binary()}
  def download_file(url, chunk_size_bytes, dir_to_download, filename \\ "", opts \\ [])
      when is_binary(url) and is_integer(chunk_size_bytes) and is_binary(dir_to_download) and
             is_binary(filename) do
    with :ok <- HTTPUtils.valid_url(url),
         :ok <- FileUtils.validate_dir?(dir_to_download) do
      opts = Keyword.merge(default_opts(), opts)
      filepath = Path.join(dir_to_download, validate_filename("", url))
      start_client(url, chunk_size_bytes, filepath, opts)
    else
      {:error, :url_not_valid} -> {:error, :url_not_valid}
      {:error, :enoent} -> {:error, :enoent}
      {:error, :no_access} -> {:error, :no_access}
      {:error, :not_directory} -> {:error, :not_directory}
    end
  end

  @doc """
  Starts `ParallelDownload.HTTPClient` process, passes given arguments in to it and monitors responses.
  """
  @spec start_client(binary(), non_neg_integer(), binary(), keyword()) ::
          {:error, any} | {:ok, any} | {:error, :server_error, any}
  def start_client(url, chunk_size_bytes, filepath, opts) do
    {:ok, pid} = HTTPClient.start_link({self(), url, chunk_size_bytes, filepath, opts})

    ref = Process.monitor(pid)

    receive do
      {:ok, path_to_file} ->
        {:ok, path_to_file}

      {:error, reason} ->
        {:error, reason}

      {:error, :server_error, reason} ->
        {:error, :server_error, reason}

      {:DOWN, ^ref, _, _proc, reason} ->
        Process.demonitor(ref, [:flush])
        {:error, reason}
    end
  end

  defp validate_filename(filename, url) do
    case filename do
      "" -> HTTPUtils.filename_from_url(url) || FileUtils.random_filename()
      _ -> Path.basename(filename)
    end
  end

  defp default_opts do
    [
      request_timeout: Application.get_env(:parallel_download, :request_timeout),
      connect_timeout: Application.get_env(:parallel_download, :connect_timeout),
      download_unsupported: Application.get_env(:parallel_download, :download_unsupported)
    ]
  end
end
