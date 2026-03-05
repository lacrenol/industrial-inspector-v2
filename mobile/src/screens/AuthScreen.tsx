import React, { useState } from "react";
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ActivityIndicator } from "react-native";
import * as SecureStore from "expo-secure-store";
import { NativeStackScreenProps } from "@react-navigation/native-stack";
import { RootStackParamList } from "../navigation";
import { supabase } from "../supabaseClient";
import { colors, spacing, radius, typography } from "../theme";

type Props = NativeStackScreenProps<RootStackParamList, "Auth">;

export const AuthScreen: React.FC<Props> = ({ navigation }) => {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleAuth = async (mode: "signIn" | "signUp") => {
    setError(null);
    setLoading(true);
    try {
      const fn = mode === "signIn" ? supabase.auth.signInWithPassword : supabase.auth.signUp;
      const { data, error: authError } = await fn({ email, password });
      if (authError || !data.session) {
        setError(authError?.message || "Authorization failed.");
        return;
      }

      const userId = data.session.user.id;
      await SecureStore.setItemAsync("accessToken", data.session.access_token);
      await SecureStore.setItemAsync("userId", userId);

      navigation.reset({
        index: 0,
        routes: [{ name: "Surveys" }]
      });
    } catch (e: any) {
      setError(e.message || "Unexpected error.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Industrial Inspector</Text>
      <Text style={styles.subtitle}>Log in to manage survey objects</Text>

      <View style={styles.card}>
        <Text style={styles.label}>Email</Text>
        <TextInput
          value={email}
          onChangeText={setEmail}
          placeholder="engineer@company.com"
          placeholderTextColor={colors.textMuted}
          keyboardType="email-address"
          autoCapitalize="none"
          style={styles.input}
        />

        <Text style={styles.label}>Password</Text>
        <TextInput
          value={password}
          onChangeText={setPassword}
          placeholder="••••••••"
          placeholderTextColor={colors.textMuted}
          secureTextEntry
          style={styles.input}
        />

        {error && <Text style={styles.error}>{error}</Text>}

        <TouchableOpacity
          style={[styles.button, loading && styles.buttonDisabled]}
          onPress={() => handleAuth("signIn")}
          disabled={loading}
        >
          {loading ? <ActivityIndicator color={colors.text} /> : <Text style={styles.buttonText}>Sign In</Text>}
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.buttonGhost, loading && styles.buttonDisabled]}
          onPress={() => handleAuth("signUp")}
          disabled={loading}
        >
          <Text style={styles.buttonGhostText}>Create account</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: spacing.lg,
    justifyContent: "center"
  },
  title: {
    ...typography.title,
    color: colors.text,
    textAlign: "center",
    marginBottom: spacing.sm
  },
  subtitle: {
    ...typography.body,
    color: colors.textMuted,
    textAlign: "center",
    marginBottom: spacing.xl
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    padding: spacing.lg,
    borderWidth: 1,
    borderColor: colors.border
  },
  label: {
    ...typography.body,
    color: colors.textMuted,
    marginBottom: spacing.xs,
    marginTop: spacing.sm
  },
  input: {
    backgroundColor: colors.surfaceAlt,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    color: colors.text,
    borderWidth: 1,
    borderColor: colors.border
  },
  button: {
    marginTop: spacing.lg,
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: "center"
  },
  buttonDisabled: {
    opacity: 0.7
  },
  buttonText: {
    ...typography.subtitle,
    color: colors.text
  },
  buttonGhost: {
    marginTop: spacing.md,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: "center",
    borderWidth: 1,
    borderColor: colors.border
  },
  buttonGhostText: {
    ...typography.body,
    color: colors.textMuted
  },
  error: {
    marginTop: spacing.sm,
    color: colors.danger,
    ...typography.body
  }
});

