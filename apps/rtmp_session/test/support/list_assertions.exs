defmodule ListAssertions.AssertionError do
  defexception expression: nil,
               message: nil

  def exception(value) do
    msg = "No entries in the list matched the expression: #{value}"
    %__MODULE__{expression: value, message: msg}
  end
end

defmodule ListAssertions do
  defmacro contains([], match_expression) do
    string_representation = Macro.to_string(match_expression) 

    quote do
      raise(ListAssertions.AssertionError, unquote(string_representation))
    end
  end

  defmacro contains([head | tail], match_expression) do
    quote do
      case unquote(head) do
        unquote(match_expression) -> :ok
        _ -> ListAssertions.contains(unquote(tail), unquote(match_expression))
      end
    end
  end
end