import React, { useState } from "react";
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ActivityIndicator, Alert } from "react-native";
import { NativeStackScreenProps } from "@react-navigation/native-stack";
import * as SecureStore from "expo-secure-store";
import { RootStackParamList } from "../navigation";
import { colors, spacing, radius, typography } from "../theme";
import { BACKEND_BASE_URL } from "../config";

type Props = NativeStackScreenProps<RootStackParamList, "NewSurvey">;

export const NewSurveyScreen: React.FC<Props> = ({ navigation }) => {
  const [name, setName] = useState("");
  const [gost, setGost] = useState("");
  const [loading, setLoading] = useState(false);

  const handleCreate = async () => {
    if (!name || !gost) {
      Alert.alert("Missing data", "Please fill in both name and GOST.");
      return;
    }
    setLoading(true);

    const userId = await SecureStore.getItemAsync("userId");
    if (!userId) {
      navigation.replace("Auth");
      return;
    }

    try {
      const res = await fetch(`${BACKEND_BASE_URL}/surveys`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          user_id: userId,
          name,
          industry_gost: gost
        })
      });

      if (!res.ok) {
        const text = await res.text();
        throw new Error(text);
      }

      navigation.goBack();
    } catch (e: any) {
      Alert.alert("Error", e.message || "Failed to create survey.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.card}>
        <Text style={styles.label}>Survey Object Name</Text>
        <TextInput
          value={name}
          onChangeText={setName}
          placeholder="Section A, column 5–7"
          placeholderTextColor={colors.textMuted}
          style={styles.input}
        />

        <Text style={styles.label}>Industry GOST</Text>
        <TextInput
          value={gost}
          onChangeText={setGost}
          placeholder="e.g. GOST 31937-2011"
          placeholderTextColor={colors.textMuted}
          style={styles.input}
        />

        <TouchableOpacity
          style={[styles.button, loading && styles.buttonDisabled]}
          onPress={handleCreate}
          disabled={loading}
        >
          {loading ? (
            <ActivityIndicator color={colors.text} />
          ) : (
            <Text style={styles.buttonText}>Create</Text>
          )}
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: spacing.lg
  },
  card: {
    backgroundColor: colors.surface,
    padding: spacing.lg,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    marginTop: spacing.lg
  },
  label: {
    ...typography.body,
    color: colors.textMuted,
    marginTop: spacing.sm,
    marginBottom: spacing.xs
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
    marginTop: spacing.xl,
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
  }
});

