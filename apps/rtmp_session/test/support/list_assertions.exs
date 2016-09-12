defmodule ListAssertions.AssertionError do
  defexception expression: nil,
               message: nil

  def exception(value) do
    msg = "No entries in the list matched the expression: #{value}"
    %__MODULE__{expression: value, message: msg}
  end
end

defmodule ListAssertions do
  defmacro __using__(_options) do
    quote do
      import ListAssertions

      defp assert_list_contains([], _fun, expression_as_string) do
        raise(ListAssertions.AssertionError, expression_as_string)  
      end

      defp assert_list_contains([head | tail], test_fun, expression_as_string) do
        case test_fun.(head) do
          true -> :ok
          false -> assert_list_contains(tail, test_fun, expression_as_string)
        end
      end
    end
  end

  defmacro contains(list, match_expression) do
    string_representation = Macro.to_string(match_expression)

    test_fun = quote do
      fn(item) -> 
        case item do
          unquote(match_expression) -> true
          _ -> false
        end
      end
    end 

    quote do
      assert_list_contains(unquote(list), unquote(test_fun), unquote(string_representation))
    end
  end
end

defmodule Test do
  use ListAssertions

  defstruct a: nil, b: nil

  def run do
    a = [1,%__MODULE__{a: 5, b: 7},3]
    ListAssertions.contains(a, %__MODULE__{b: 7})

    IO.puts("Match success")
  end
end

Test.run