namespace TaigaMCP.Api;

internal static class InputValidation
{
    public static void Positive(int value, string name)
    {
        if (value <= 0) throw new ArgumentException($"{name} must be positive.");
    }

    public static void Nonnegative(int value, string name)
    {
        if (value < 0) throw new ArgumentException($"{name} must be nonnegative.");
    }

    public static void Required(string? value, string name)
    {
        if (string.IsNullOrWhiteSpace(value)) throw new ArgumentException($"{name} must not be blank.");
    }

    public static void OptionalIds(params (int? Value, string Name)[] fields)
    {
        foreach (var (value, name) in fields)
            if (value.HasValue) Positive(value.Value, name);
    }
}
