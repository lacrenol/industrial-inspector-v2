import React, { useRef, useState } from "react";
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Image, TextInput, Alert } from "react-native";
import { CameraView, useCameraPermissions } from "expo-camera";
import { NativeStackScreenProps } from "@react-navigation/native-stack";
import { RootStackParamList } from "../navigation";
import { colors, spacing, radius, typography } from "../theme";
import { supabase } from "../supabaseClient";
import { BACKEND_BASE_URL, SUPABASE_IMAGE_BUCKET } from "../config";

type Props = NativeStackScreenProps<RootStackParamList, "Camera">;

type Axis = "X" | "Y";
type ConstructionType = "Concrete" | "Brick" | "Metal" | "Roof";

export const CameraScreen: React.FC<Props> = ({ route }) => {
  const { surveyId } = route.params;
  const [permission, requestPermission] = useCameraPermissions();
  const cameraRef = useRef<CameraView | null>(null);

  const [axis, setAxis] = useState<Axis>("X");
  const [constructionType, setConstructionType] = useState<ConstructionType>("Concrete");
  const [location, setLocation] = useState("");

  const [previewUri, setPreviewUri] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [analysis, setAnalysis] = useState<{ description: string; status_category: string } | null>(null);

  if (!permission) {
    return <View />;
  }

  if (!permission.granted) {
    return (
      <View style={styles.permissionContainer}>
        <Text style={styles.permissionText}>Camera access is required to capture defects.</Text>
        <TouchableOpacity style={styles.permissionButton} onPress={requestPermission}>
          <Text style={styles.permissionButtonText}>Grant permission</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const handleTakePhoto = async () => {
    if (!cameraRef.current) return;
    setAnalysis(null);
    const photo = await cameraRef.current.takePictureAsync({ quality: 0.6 });
    setPreviewUri(photo.uri);
  };

  const handleSend = async () => {
    if (!previewUri) return;
    try {
      setLoading(true);

      // Upload image to Supabase Storage
      const fileExt = "jpg";
      const fileName = `survey-${surveyId}-${Date.now()}.${fileExt}`;

      const res = await fetch(previewUri);
      const blob = await res.blob();

      const { data, error } = await supabase.storage
        .from(SUPABASE_IMAGE_BUCKET)
        .upload(fileName, blob, {
          contentType: "image/jpeg"
        });

      if (error || !data?.path) {
        throw new Error(error?.message || "Failed to upload image.");
      }

      const { data: publicData } = supabase.storage.from(SUPABASE_IMAGE_BUCKET).getPublicUrl(data.path);
      const imageUrl = publicData.publicUrl;

      // Call backend for analysis
      const resp = await fetch(`${BACKEND_BASE_URL}/defects/analyze`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          survey_id: surveyId,
          image_url: imageUrl,
          axis,
          construction_type: constructionType,
          location: location || null
        })
      });

      if (!resp.ok) {
        const text = await resp.text();
        throw new Error(text);
      }

      const json = await resp.json();
      setAnalysis({
        description: json.description,
        status_category: json.status_category
      });
      Alert.alert("Analysis complete", `Status: ${json.status_category}`);
    } catch (e: any) {
      Alert.alert("Error", e.message || "Failed to send data.");
    } finally {
      setLoading(false);
    }
  };

  const axisButton = (value: Axis) => (
    <TouchableOpacity
      key={value}
      style={[styles.chip, axis === value && styles.chipActive]}
      onPress={() => setAxis(value)}
    >
      <Text style={[styles.chipText, axis === value && styles.chipTextActive]}>{value}</Text>
    </TouchableOpacity>
  );

  const constructionButton = (value: ConstructionType) => (
    <TouchableOpacity
      key={value}
      style={[styles.chip, constructionType === value && styles.chipActive]}
      onPress={() => setConstructionType(value)}
    >
      <Text
        style={[
          styles.chipText,
          constructionType === value && styles.chipTextActive
        ]}
      >
        {value}
      </Text>
    </TouchableOpacity>
  );

  return (
    <View style={styles.container}>
      {previewUri ? (
        <Image source={{ uri: previewUri }} style={styles.preview} />
      ) : (
        <CameraView style={styles.camera} ref={cameraRef} facing="back" />
      )}

      <View style={styles.panel}>
        <Text style={styles.panelTitle}>Capture parameters</Text>

        <Text style={styles.label}>Axis</Text>
        <View style={styles.row}>
          {axisButton("X")}
          {axisButton("Y")}
        </View>

        <Text style={styles.label}>Construction type</Text>
        <View style={styles.row}>
          {(["Concrete", "Brick", "Metal", "Roof"] as ConstructionType[]).map(constructionButton)}
        </View>

        <Text style={styles.label}>Location (optional)</Text>
        <TextInput
          value={location}
          onChangeText={setLocation}
          placeholder="Axis X5–X6, level +3.600"
          placeholderTextColor={colors.textMuted}
          style={styles.input}
        />

        {analysis && (
          <View style={styles.analysisCard}>
            <Text style={styles.analysisTitle}>Gemini result</Text>
            <Text style={styles.analysisStatus}>Status category: {analysis.status_category}</Text>
            <Text style={styles.analysisText}>{analysis.description}</Text>
          </View>
        )}

        <View style={styles.actionsRow}>
          <TouchableOpacity
            style={[styles.actionButton, styles.secondaryButton]}
            onPress={handleTakePhoto}
            disabled={loading}
          >
            <Text style={styles.secondaryButtonText}>
              {previewUri ? "Retake" : "Capture"}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.actionButton, styles.primaryButton, loading && styles.buttonDisabled]}
            onPress={handleSend}
            disabled={loading || !previewUri}
          >
            {loading ? (
              <ActivityIndicator color={colors.text} />
            ) : (
              <Text style={styles.primaryButtonText}>Send to backend</Text>
            )}
          </TouchableOpacity>
        </View>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background
  },
  camera: {
    flex: 1
  },
  preview: {
    flex: 1,
    resizeMode: "cover"
  },
  panel: {
    backgroundColor: colors.surface,
    padding: spacing.md,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    borderTopWidth: 1,
    borderColor: colors.border
  },
  panelTitle: {
    ...typography.subtitle,
    color: colors.text,
    marginBottom: spacing.sm
  },
  label: {
    ...typography.body,
    color: colors.textMuted,
    marginTop: spacing.sm,
    marginBottom: spacing.xs
  },
  row: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: spacing.sm
  } as any,
  chip: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surfaceAlt
  },
  chipActive: {
    borderColor: colors.primary,
    backgroundColor: "#20150F"
  },
  chipText: {
    ...typography.body,
    color: colors.textMuted
  },
  chipTextActive: {
    color: colors.primaryAlt
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
  actionsRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    marginTop: spacing.md
  },
  actionButton: {
    flex: 1,
    paddingVertical: spacing.sm,
    borderRadius: radius.md,
    alignItems: "center",
    justifyContent: "center",
    marginHorizontal: spacing.xs
  },
  primaryButton: {
    backgroundColor: colors.primary
  },
  secondaryButton: {
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surfaceAlt
  },
  primaryButtonText: {
    ...typography.body,
    color: colors.text
  },
  secondaryButtonText: {
    ...typography.body,
    color: colors.textMuted
  },
  buttonDisabled: {
    opacity: 0.7
  },
  analysisCard: {
    marginTop: spacing.md,
    padding: spacing.md,
    borderRadius: radius.md,
    backgroundColor: colors.surfaceAlt,
    borderWidth: 1,
    borderColor: colors.border
  },
  analysisTitle: {
    ...typography.subtitle,
    color: colors.text,
    marginBottom: spacing.xs
  },
  analysisStatus: {
    ...typography.body,
    color: colors.accent,
    marginBottom: spacing.xs
  },
  analysisText: {
    ...typography.body,
    color: colors.textMuted
  },
  permissionContainer: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: "center",
    justifyContent: "center",
    padding: spacing.lg
  },
  permissionText: {
    ...typography.body,
    color: colors.text,
    textAlign: "center",
    marginBottom: spacing.md
  },
  permissionButton: {
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg
  },
  permissionButtonText: {
    ...typography.subtitle,
    color: colors.text
  }
});

