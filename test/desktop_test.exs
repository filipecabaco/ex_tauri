defmodule DesktopTest do
  use ExUnit.Case
  doctest Desktop

  test "greets the world" do
    assert Desktop.hello() == :world
  end
end
