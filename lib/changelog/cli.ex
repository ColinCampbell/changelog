defmodule Changelog.CLI do
  @moduledoc "Shared entrypoint for the task and escript"

  def main(argv \\ []) do
    run(argv)
  end

  @doc false
  def run(["help"]) do
    IO.puts("""
    Usage: mix changelog <package>

    Run without any arguments to fetch the changelogs of all packages.
    """)
  end

  def run(argv) do
    Changelog.Application.start(nil, nil)

    lock = Mix.Dep.Lock.read()
    packages = Hex.Mix.packages_from_lock(lock)

    case argv do
      [] ->
        print(lock, fetch_changelogs(packages))

      only_packages ->
        print(
          lock,
          fetch_changelogs(Enum.filter(packages, fn {_, package} -> package in only_packages end))
        )
    end
  end

  defp print(lock, changelogs) do
    for {package_name, %{changelog: changelog, latest_version: latest_version}} <- changelogs do
      version = lock[String.to_atom(package_name)] |> elem(2)

      if version != latest_version do
        IO.puts("""
        Package: #{package_name}
        Current version: #{version}
        Latest version:  #{latest_version}
        Hexdiff: https://diff.hex.pm/diff/#{package_name}/#{version}..#{latest_version}

        #{changelog_output(version, latest_version, changelog)}
        --------------------------
        """)
      end
    end
  end

  defp changelog_output(version, version, _changelog), do: "Package is up to date"

  defp changelog_output(current_version, _latest_version, changelog) do
    String.replace(changelog, ~r/##? +v?#{current_version}.*/s, "")
  end

  defp fetch_changelogs(packages) do
    hex_config =
      put_in(:hex_core.default_config(), [:http_adapter], {Changelog.HexHTTPAdapter, []})

    for {_, package} <- packages, into: %{} do
      case :hex_api_package.get(hex_config, package) do
        {:ok,
         {_status, _headers, %{"latest_version" => latest_version, "meta" => %{"links" => links}}}} ->
          {package, %{latest_version: latest_version, changelog: fetch_changelog(links)}}

        _ ->
          {package, %{}}
      end
    end
  end

  defp fetch_changelog(links) do
    {_, github_url} = Enum.find(links, fn {k, _} -> k =~ ~r/github/i end)

    do_fetch_changelog(github_url, :master) ||
      do_fetch_changelog(github_url, :main) ||
      "Changelog not found"
  end

  defp do_fetch_changelog("https://github.com/" <> repo, branch) do
    case Req.get!("https://raw.githubusercontent.com/#{repo}/#{branch}/CHANGELOG.md") do
      %{status: 200, body: body} -> body
      _ -> nil
    end
  end

  defp do_fetch_changelog(_, _), do: nil
end